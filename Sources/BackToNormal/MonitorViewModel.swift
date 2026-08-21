import Foundation
import SwiftUI
import BackToNormalCore

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
    @Published private(set) var isScanningCleanup = false
    @Published private(set) var isCleaning = false
    @Published var isShowingCleanupConfirmation = false

    private var timer: Timer?
    private var lastStorageScan: Date?
    static let refreshInterval: TimeInterval = 30
    static let storageRefreshInterval: TimeInterval = 10 * 60

    init() {
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
        guard !isRefreshing else { return }
        isRefreshing = true
        let cachedStorage = storage
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
                if shouldScanStorage { self.lastStorageScan = Date() }
                self.lastRefreshed = Date()
                self.isRefreshing = false
            }
        }
    }

    func scanCleanupCandidates() {
        guard !isScanningCleanup, !isCleaning else { return }
        isScanningCleanup = true
        cleanupResults = []
        processCleanupResults = []
        Task.detached(priority: .utility) {
            let input = CleanupEvidenceCollector.collect()
            let candidates = CleanupPolicy.propose(input)
            let processCandidates = ProcessCleanupPolicy.propose(Self.processCleanupInput())
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.cleanupCandidates = candidates
                // 새 스캔 결과는 디스크와 프로세스 모두 안전하게 기본 미선택으로 시작한다.
                self.selectedCleanupIDs.removeAll()
                self.processCleanupCandidates = processCandidates
                self.selectedProcessCleanupIDs.removeAll()
                self.isScanningCleanup = false
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
        if selectedCleanupIDs.contains(candidate.id) {
            selectedCleanupIDs.remove(candidate.id)
        } else {
            selectedCleanupIDs.insert(candidate.id)
        }
    }

    func toggleProcessCleanupCandidate(_ candidate: ProcessCleanupCandidate) {
        if selectedProcessCleanupIDs.contains(candidate.id) {
            selectedProcessCleanupIDs.remove(candidate.id)
        } else {
            selectedProcessCleanupIDs.insert(candidate.id)
        }
    }

    func requestCleanupConfirmation() {
        guard !selectedCandidates.isEmpty || !selectedProcessCandidates.isEmpty else { return }
        isShowingCleanupConfirmation = true
    }

    func executeSelectedCleanup() {
        let targets = selectedCandidates
        let processTargets = selectedProcessCandidates
        guard !targets.isEmpty || !processTargets.isEmpty, !isCleaning else { return }
        isShowingCleanupConfirmation = false
        isCleaning = true

        Task.detached(priority: .utility) {
            let results = targets.map(CleanupExecutor.execute)
            let processResults = processTargets.map(ProcessCleanupExecutor.execute)
            let refreshedInput = CleanupEvidenceCollector.collect()
            let refreshedCandidates = CleanupPolicy.propose(refreshedInput)
            let refreshedProcessCandidates = ProcessCleanupPolicy.propose(Self.processCleanupInput())
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.cleanupResults = results
                self.processCleanupResults = processResults
                self.cleanupCandidates = refreshedCandidates
                self.processCleanupCandidates = refreshedProcessCandidates
                self.selectedCleanupIDs.removeAll()
                self.selectedProcessCleanupIDs.removeAll()
                self.isCleaning = false
                self.lastStorageScan = nil
                self.refresh()
            }
        }
    }

    var selectedCandidates: [CleanupCandidate] {
        cleanupCandidates.filter { selectedCleanupIDs.contains($0.id) }
    }

    var selectedProcessCandidates: [ProcessCleanupCandidate] {
        processCleanupCandidates.filter { selectedProcessCleanupIDs.contains($0.id) }
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
