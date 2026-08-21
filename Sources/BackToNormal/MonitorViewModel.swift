import Foundation
import SwiftUI
import BackToNormalCore

enum CleanupActivity: Equatable {
    case idle
    case scanning
    case cleaning
    case autoCleaning
}

/// 수집 → 진단 → 화면 상태를 잇는 뷰모델. 30초마다 자동 새로고침한다.
@MainActor
final class MonitorViewModel: ObservableObject {
    @Published private(set) var diagnosis = DiagnosticEngine.evaluate(metrics: nil, processes: [])
    @Published private(set) var metrics: MetricsSnapshot?
    @Published private(set) var storage: StorageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshed: Date?
    @Published private(set) var cleanupCandidates: [CleanupCandidate] = []
    @Published var selectedCleanupIDs: Set<String> = []
    @Published private(set) var cleanupResults: [CleanupExecutionResult] = []
    @Published private(set) var processCleanupCandidates: [ProcessCleanupCandidate] = []
    @Published var selectedProcessCleanupIDs: Set<String> = []
    @Published private(set) var processCleanupResults: [ProcessCleanupExecutionResult] = []
    @Published private(set) var cleanupActivity: CleanupActivity = .idle
    @Published var isShowingCleanupConfirmation = false
    @Published private(set) var cleanupImpact: CleanupImpactSummary?
    @Published private(set) var cleanupHistory: [CleanupAuditEntry] = []
    @Published private(set) var protectedCleanupIDs: Set<String> = []
    @Published private(set) var automaticCleanupSummary: String?

    private var timer: Timer?
    private var lastStorageScan: Date?
    /// 새로고침 진행 중에 들어온 요청을 잃지 않고 완료 직후 한 번 더 실행하기 위한 플래그.
    private var isRefreshQueued = false
    /// 저장 공간 스캔 무효화 세대. 무효화 이전에 시작한 스캔이 lastStorageScan을 덮어쓰지 못하게 한다.
    private var storageScanGeneration = 0
    private let auditStore: CleanupAuditStore
    private let protectionStore: CleanupProtectionStore
    static let refreshInterval: TimeInterval = 30
    static let storageRefreshInterval: TimeInterval = 10 * 60

    var isScanningCleanup: Bool { cleanupActivity == .scanning }
    var isAutoCleaning: Bool { cleanupActivity == .autoCleaning }
    var isCleaning: Bool { cleanupActivity == .cleaning || cleanupActivity == .autoCleaning }
    var isCleanupBusy: Bool { cleanupActivity != .idle }

    init(
        auditStore: CleanupAuditStore = CleanupAuditStore(),
        protectionStore: CleanupProtectionStore = CleanupProtectionStore()
    ) {
        self.auditStore = auditStore
        self.protectionStore = protectionStore
        cleanupHistory = auditStore.load()
        protectedCleanupIDs = protectionStore.load()
        startAutoRefresh()
        refresh()
    }

    func startAutoRefresh() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard !isRefreshing else {
            isRefreshQueued = true
            return
        }
        isRefreshing = true
        let cachedStorage = storage
        let generation = storageScanGeneration
        let shouldScanStorage = lastStorageScan.map {
            Date().timeIntervalSince($0) >= Self.storageRefreshInterval
        } ?? true

        Task.detached(priority: .utility) {
            let metrics = MetricsCollector.collect()
            let processes = ProcessCollector.collect()
            let storage = shouldScanStorage ? StorageCollector.collect() : cachedStorage
            let diagnosis = DiagnosticEngine.evaluate(metrics: metrics, processes: processes, storage: storage)

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.metrics = metrics
                self.storage = storage
                self.diagnosis = diagnosis
                // 스캔 시작 후 정리가 무효화한 경우 lastStorageScan을 되살리지 않는다.
                if shouldScanStorage, generation == self.storageScanGeneration {
                    self.lastStorageScan = Date()
                }
                self.lastRefreshed = Date()
                self.isRefreshing = false
                if self.isRefreshQueued {
                    self.isRefreshQueued = false
                    self.refresh()
                }
            }
        }
    }

    /// 정리 이후 저장 공간 캐시를 무효화한다. 진행 중인 스캔이 이 결정을 덮어쓰지 못하게 세대를 올린다.
    private func invalidateStorageScan() {
        lastStorageScan = nil
        storageScanGeneration += 1
    }

    func scanCleanupCandidates() {
        guard cleanupActivity == .idle else { return }
        cleanupActivity = .scanning
        cleanupResults = []
        processCleanupResults = []
        automaticCleanupSummary = nil
        Task.detached(priority: .utility) {
            let input = CleanupEvidenceCollector.collect()
            let candidates = CleanupPolicy.propose(input)
            let processCandidates = ProcessCleanupPolicy.propose(Self.processCleanupInput())
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.cleanupCandidates = candidates.filter { !self.protectedCleanupIDs.contains($0.id) }
                // 새 스캔 결과는 디스크와 프로세스 모두 안전하게 기본 미선택으로 시작한다.
                self.selectedCleanupIDs.removeAll()
                self.processCleanupCandidates = processCandidates.filter {
                    !self.protectedCleanupIDs.contains($0.protectionIdentifier)
                }
                self.selectedProcessCleanupIDs.removeAll()
                self.cleanupActivity = .idle
            }
        }
    }

    /// 신선한 근거를 수집해 저위험이면서 휴지통 복구 가능한 파일만 무확인으로 정리한다.
    /// 그 후 시뮬레이터 정리 후보(데이터 초기화·사용 불가·임시 복제)가 남아 있으면
    /// 해당 후보만 선택해 기존 최종 확인 창을 연다. 확인 없이는 어떤 시뮬레이터도 지우지 않으며,
    /// 프로세스 종료와 그 밖의 중간 위험 파일 후보는 자동 선택하지 않는다.
    func runAutomaticCleanup() {
        guard cleanupActivity == .idle else { return }
        cleanupActivity = .autoCleaning
        cleanupResults = []
        processCleanupResults = []
        automaticCleanupSummary = nil
        selectedCleanupIDs.removeAll()
        selectedProcessCleanupIDs.removeAll()
        isShowingCleanupConfirmation = false
        let protectedIdentifiers = protectedCleanupIDs

        Task.detached(priority: .utility) {
            let input = CleanupEvidenceCollector.collect()
            let proposed = CleanupPolicy.propose(input)
            let plan = AutomaticCleanupPolicy.makePlan(
                candidates: proposed,
                protectedIdentifiers: protectedIdentifiers
            )
            let proposedProcesses = ProcessCleanupPolicy.propose(Self.processCleanupInput())
                .filter { !protectedIdentifiers.contains($0.protectionIdentifier) }

            let beforeImpact = plan.targets.isEmpty ? nil : SystemImpactCollector.collect()
            let results = plan.targets.map(CleanupExecutor.execute)
            let afterImpact = plan.targets.isEmpty ? nil : SystemImpactCollector.collect()
            let impact = beforeImpact.flatMap { before in
                afterImpact.map { after in
                    CleanupImpactSummary(
                        beforeMetrics: before.metrics,
                        afterMetrics: after.metrics,
                        beforeDiskAvailableBytes: before.diskAvailableBytes,
                        afterDiskAvailableBytes: after.diskAvailableBytes,
                        completedAt: Date()
                    )
                }
            }
            let auditEntries = Self.makeAuditEntries(results: results, processResults: [])

            let refreshedInput = CleanupEvidenceCollector.collect()
            let refreshedCandidates = CleanupPolicy.propose(refreshedInput)
                .filter { !protectedIdentifiers.contains($0.id) }
            let refreshedProcessCandidates = ProcessCleanupPolicy.propose(Self.processCleanupInput())
                .filter { !protectedIdentifiers.contains($0.protectionIdentifier) }
            // 시뮬레이터 후보만 최종 확인 창으로 넘긴다. 프로세스와 중간 위험 파일 후보는 넘기지 않는다.
            let simulatorFollowUps = refreshedCandidates.filter { $0.kind.targetsSimulator }
            let cleanedCount = results.filter { $0.status == .cleaned }.count
            let failedCount = results.count - cleanedCount
            let manualOnlyCount = plan.manualOnly.filter { !$0.kind.targetsSimulator }.count
                + proposedProcesses.count
            let summary = Self.automaticSummary(
                cleanedCount: cleanedCount,
                failedCount: failedCount,
                manualOnlyCount: manualOnlyCount,
                simulatorConfirmationCount: simulatorFollowUps.count
            )

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.cleanupResults = results
                self.processCleanupResults = []
                self.cleanupImpact = impact
                self.cleanupHistory = self.auditStore.append(auditEntries, to: self.cleanupHistory)
                self.cleanupCandidates = refreshedCandidates
                self.processCleanupCandidates = refreshedProcessCandidates
                self.selectedCleanupIDs = Set(simulatorFollowUps.map(\.id))
                self.selectedProcessCleanupIDs.removeAll()
                self.automaticCleanupSummary = summary
                self.cleanupActivity = .idle
                // 시뮬레이터 정리는 자동 실행하지 않고 기존 최종 확인 창에서 승인받는다.
                self.isShowingCleanupConfirmation = !simulatorFollowUps.isEmpty
                if cleanedCount > 0 { self.invalidateStorageScan() }
                self.refresh()
            }
        }
    }

    nonisolated static func processCleanupInput() -> ProcessCleanupPolicyInput {
        ProcessCleanupPolicyInput(
            processes: ProcessCollector.collectOptional(),
            currentUserName: NSUserName(),
            ownPid: ProcessInfo.processInfo.processIdentifier
        )
    }

    func toggleCleanupCandidate(_ candidate: CleanupCandidate) {
        guard cleanupActivity == .idle else { return }
        if selectedCleanupIDs.contains(candidate.id) {
            selectedCleanupIDs.remove(candidate.id)
        } else {
            selectedCleanupIDs.insert(candidate.id)
        }
    }

    func toggleProcessCleanupCandidate(_ candidate: ProcessCleanupCandidate) {
        guard cleanupActivity == .idle, candidate.isActionable else { return }
        if selectedProcessCleanupIDs.contains(candidate.id) {
            selectedProcessCleanupIDs.remove(candidate.id)
        } else {
            selectedProcessCleanupIDs.insert(candidate.id)
        }
    }

    func protectCleanupCandidate(id: String) {
        guard cleanupActivity == .idle else { return }
        protectedCleanupIDs.insert(id)
        protectionStore.save(protectedCleanupIDs)
        selectedCleanupIDs.remove(id)
        cleanupCandidates.removeAll { $0.id == id }
        let protectedProcessIDs = processCleanupCandidates
            .filter { $0.protectionIdentifier == id }
            .map(\.id)
        selectedProcessCleanupIDs.subtract(protectedProcessIDs)
        processCleanupCandidates.removeAll { $0.protectionIdentifier == id }
    }

    func clearProtections() {
        guard cleanupActivity == .idle else { return }
        protectedCleanupIDs.removeAll()
        protectionStore.save(protectedCleanupIDs)
        scanCleanupCandidates()
    }

    func requestCleanupConfirmation() {
        guard cleanupActivity == .idle,
              !selectedCandidates.isEmpty || !selectedProcessCandidates.isEmpty
        else { return }
        isShowingCleanupConfirmation = true
    }

    func executeSelectedCleanup() {
        let targets = selectedCandidates
        let processTargets = selectedProcessCandidates
        guard !targets.isEmpty || !processTargets.isEmpty, cleanupActivity == .idle else { return }
        isShowingCleanupConfirmation = false
        cleanupActivity = .cleaning
        automaticCleanupSummary = nil

        Task.detached(priority: .utility) {
            let beforeImpact = SystemImpactCollector.collect()
            let results = targets.map(CleanupExecutor.execute)
            let processResults = processTargets.map { ProcessCleanupExecutor.execute($0) }
            let afterImpact = SystemImpactCollector.collect()
            let impact = CleanupImpactSummary(
                beforeMetrics: beforeImpact.metrics,
                afterMetrics: afterImpact.metrics,
                beforeDiskAvailableBytes: beforeImpact.diskAvailableBytes,
                afterDiskAvailableBytes: afterImpact.diskAvailableBytes,
                completedAt: Date()
            )
            let auditEntries = Self.makeAuditEntries(results: results, processResults: processResults)
            let refreshedInput = CleanupEvidenceCollector.collect()
            let refreshedCandidates = CleanupPolicy.propose(refreshedInput)
            let refreshedProcessCandidates = ProcessCleanupPolicy.propose(Self.processCleanupInput())
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.cleanupResults = results
                self.processCleanupResults = processResults
                self.cleanupImpact = impact
                self.cleanupHistory = self.auditStore.append(auditEntries, to: self.cleanupHistory)
                self.cleanupCandidates = refreshedCandidates.filter { !self.protectedCleanupIDs.contains($0.id) }
                self.processCleanupCandidates = refreshedProcessCandidates.filter {
                    !self.protectedCleanupIDs.contains($0.protectionIdentifier)
                }
                self.selectedCleanupIDs.removeAll()
                self.selectedProcessCleanupIDs.removeAll()
                self.cleanupActivity = .idle
                self.invalidateStorageScan()
                self.refresh()
            }
        }
    }

    nonisolated private static func makeAuditEntries(
        results: [CleanupExecutionResult],
        processResults: [ProcessCleanupExecutionResult]
    ) -> [CleanupAuditEntry] {
        let now = Date()
        return results.map {
            CleanupAuditEntry(
                id: UUID(), timestamp: now, category: $0.candidate.kind.koreanLabel,
                target: $0.candidate.targetIdentifier, status: $0.status, message: $0.message
            )
        } + processResults.map {
            CleanupAuditEntry(
                id: UUID(), timestamp: now, category: $0.candidate.kind.koreanLabel,
                target: "pid \($0.candidate.pid)", status: $0.status, message: $0.message
            )
        }
    }

    nonisolated private static func automaticSummary(
        cleanedCount: Int,
        failedCount: Int,
        manualOnlyCount: Int,
        simulatorConfirmationCount: Int
    ) -> String {
        var parts: [String] = ["안전한 파일 자동 정리 \(cleanedCount)개 완료"]
        if failedCount > 0 { parts.append("\(failedCount)개 차단 또는 실패") }
        if simulatorConfirmationCount > 0 {
            parts.append("시뮬레이터 정리 \(simulatorConfirmationCount)개는 최종 확인 후에만 실행")
        }
        if manualOnlyCount > 0 {
            parts.append("\(manualOnlyCount)개는 수동 확인 필요")
        }
        if simulatorConfirmationCount == 0 && manualOnlyCount == 0 {
            parts.append("비가역 작업과 프로세스 종료는 실행하지 않음")
        }
        return parts.joined(separator: " · ")
    }

    var selectedCandidates: [CleanupCandidate] {
        cleanupCandidates.filter { selectedCleanupIDs.contains($0.id) }
    }

    var selectedProcessCandidates: [ProcessCleanupCandidate] {
        processCleanupCandidates.filter { $0.isActionable && selectedProcessCleanupIDs.contains($0.id) }
    }

    /// 선택된 디스크 후보의 예상 확보 공간. 메모리 예상치와 절대 합산하지 않는다.
    var selectedCleanupBytes: UInt64 {
        selectedCandidates.reduce(0) { $0 + $1.estimatedBytes }
    }

    /// 선택된 프로세스 후보의 상주 메모리 합계. 디스크 예상치와 별도로만 표시한다.
    var selectedProcessMemoryBytes: UInt64 {
        ProcessCleanupPolicy.totalExpectedResidentBytes(of: selectedProcessCandidates)
    }

    var statusSymbolName: String {
        if isRefreshing { return "arrow.triangle.2.circlepath" }
        switch diagnosis.status {
        case .scanning: return "magnifyingglass"
        case .healthy: return "checkmark.circle"
        case .caution: return "exclamationmark.triangle"
        case .pressure: return "exclamationmark.octagon"
        }
    }

    var statusColor: Color {
        switch diagnosis.status {
        case .scanning: return .gray
        case .healthy: return .green
        case .caution: return .yellow
        case .pressure: return .red
        }
    }
}
