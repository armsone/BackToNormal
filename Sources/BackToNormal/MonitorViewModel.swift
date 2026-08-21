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
        Task.detached(priority: .utility) {
            let input = CleanupEvidenceCollector.collect()
            let candidates = CleanupPolicy.propose(input)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.cleanupCandidates = candidates
                self.selectedCleanupIDs.formIntersection(Set(candidates.map(\.id)))
                self.isScanningCleanup = false
            }
        }
    }

    func toggleCleanupCandidate(_ candidate: CleanupCandidate) {
        if selectedCleanupIDs.contains(candidate.id) {
            selectedCleanupIDs.remove(candidate.id)
        } else {
            selectedCleanupIDs.insert(candidate.id)
        }
    }

    func requestCleanupConfirmation() {
        guard !selectedCandidates.isEmpty else { return }
        isShowingCleanupConfirmation = true
    }

    func executeSelectedCleanup() {
        let targets = selectedCandidates
        guard !targets.isEmpty, !isCleaning else { return }
        isShowingCleanupConfirmation = false
        isCleaning = true

        Task.detached(priority: .utility) {
            let results = targets.map(CleanupExecutor.execute)
            let refreshedInput = CleanupEvidenceCollector.collect()
            let refreshedCandidates = CleanupPolicy.propose(refreshedInput)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.cleanupResults = results
                self.cleanupCandidates = refreshedCandidates
                self.selectedCleanupIDs.removeAll()
                self.isCleaning = false
                self.lastStorageScan = nil
                self.refresh()
            }
        }
    }

    var selectedCandidates: [CleanupCandidate] {
        cleanupCandidates.filter { selectedCleanupIDs.contains($0.id) }
    }

    var selectedCleanupBytes: UInt64 {
        selectedCandidates.reduce(0) { $0 + $1.estimatedBytes }
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
