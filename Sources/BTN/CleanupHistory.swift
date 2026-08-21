import Foundation
import BTNCore

struct CleanupImpactSummary: Sendable {
    let beforeMetrics: MetricsSnapshot
    let afterMetrics: MetricsSnapshot
    let beforeDiskAvailableBytes: UInt64?
    let afterDiskAvailableBytes: UInt64?
    let completedAt: Date
}

enum SystemImpactCollector {
    static func collect() -> (metrics: MetricsSnapshot, diskAvailableBytes: UInt64?) {
        let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        let diskBytes = values?.volumeAvailableCapacityForImportantUsage.flatMap { value in
            value >= 0 ? UInt64(value) : nil
        }
        return (MetricsCollector.collect(), diskBytes)
    }
}

struct CleanupAuditEntry: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let category: String
    let target: String
    let status: CleanupExecutionStatus
    let message: String
}

final class CleanupAuditStore {
    private let fileURL: URL
    private let maximumEntries: Int

    init(
        fileURL: URL? = nil,
        maximumEntries: Int = 200,
        applicationSupportDirectory: URL? = nil
    ) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let applicationSupport = applicationSupportDirectory ?? FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let currentURL = applicationSupport
                .appendingPathComponent("BTN", isDirectory: true)
                .appendingPathComponent("cleanup-history.json")
            let legacyURL = applicationSupport
                .appendingPathComponent("BackToNormal", isDirectory: true)
                .appendingPathComponent("cleanup-history.json")
            var resolvedURL = currentURL

            if !FileManager.default.fileExists(atPath: currentURL.path),
               FileManager.default.fileExists(atPath: legacyURL.path) {
                do {
                    try FileManager.default.createDirectory(
                        at: currentURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try FileManager.default.copyItem(at: legacyURL, to: currentURL)
                } catch {
                    resolvedURL = legacyURL
                }
            }
            self.fileURL = resolvedURL
        }
        self.maximumEntries = max(1, maximumEntries)
    }

    func load() -> [CleanupAuditEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? JSONDecoder().decode([CleanupAuditEntry].self, from: data)
        else { return [] }
        return Array(entries.suffix(maximumEntries))
    }

    @discardableResult
    func append(_ newEntries: [CleanupAuditEntry], to existing: [CleanupAuditEntry]) -> [CleanupAuditEntry] {
        guard !newEntries.isEmpty else { return existing }
        let merged = Array((existing + newEntries).suffix(maximumEntries))
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(merged)
            try data.write(to: fileURL, options: .atomic)
            return merged
        } catch {
            // 이력 저장 실패가 실제 정리 결과를 바꾸거나 재시도하게 만들면 안 된다.
            return existing
        }
    }
}

final class CleanupProtectionStore {
    private let defaults: UserDefaults
    private let key = "protectedCleanupCandidateIDs"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    func save(_ identifiers: Set<String>) {
        defaults.set(identifiers.sorted(), forKey: key)
    }
}
