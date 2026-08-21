import XCTest
@testable import BTN

final class CleanupHistoryTests: XCTestCase {
    func testAuditStorePersistsAndCapsNewestEntries() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CleanupAuditStore(
            fileURL: directory.appendingPathComponent("history.json"),
            maximumEntries: 2
        )
        let entries = (1...3).map { index in
            CleanupAuditEntry(
                id: UUID(), timestamp: Date(timeIntervalSince1970: Double(index)),
                category: "test", target: "target-\(index)", status: .cleaned, message: "done"
            )
        }

        let saved = store.append(entries, to: [])

        XCTAssertEqual(saved.map(\.target), ["target-2", "target-3"])
        XCTAssertEqual(store.load(), saved)
    }

    func testAuditStoreFailureDoesNotInventHistory() {
        let store = CleanupAuditStore(fileURL: URL(fileURLWithPath: "/dev/null/history.json"))
        let entry = CleanupAuditEntry(
            id: UUID(), timestamp: Date(), category: "test", target: "target",
            status: .failed, message: "failed"
        )

        XCTAssertEqual(store.append([entry], to: []), [])
    }

    func testAuditStoreCopiesLegacyHistoryOnFirstLaunch() throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let legacyURL = applicationSupport
            .appendingPathComponent("BackToNormal", isDirectory: true)
            .appendingPathComponent("cleanup-history.json")
        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let legacyEntry = CleanupAuditEntry(
            id: UUID(), timestamp: Date(timeIntervalSince1970: 1), category: "test",
            target: "legacy", status: .cleaned, message: "done"
        )
        try JSONEncoder().encode([legacyEntry]).write(to: legacyURL)

        let store = CleanupAuditStore(applicationSupportDirectory: applicationSupport)

        XCTAssertEqual(store.load(), [legacyEntry])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: applicationSupport
                .appendingPathComponent("BTN/cleanup-history.json")
                .path
        ))
    }

    func testAuditStoreKeepsUsingLegacyHistoryWhenCopyFails() throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let legacyURL = applicationSupport
            .appendingPathComponent("BackToNormal", isDirectory: true)
            .appendingPathComponent("cleanup-history.json")
        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let legacyEntry = CleanupAuditEntry(
            id: UUID(), timestamp: Date(timeIntervalSince1970: 1), category: "test",
            target: "legacy", status: .cleaned, message: "done"
        )
        try JSONEncoder().encode([legacyEntry]).write(to: legacyURL)
        try Data().write(to: applicationSupport.appendingPathComponent("BTN"))

        let store = CleanupAuditStore(applicationSupportDirectory: applicationSupport)

        XCTAssertEqual(store.load(), [legacyEntry])
    }

    func testProtectionStoreRoundTripsStableIdentifiers() {
        let suiteName = "BTNTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CleanupProtectionStore(defaults: defaults)

        store.save(["proc:gradleDaemon:500", "derived:/tmp/example"])

        XCTAssertEqual(store.load(), ["proc:gradleDaemon:500", "derived:/tmp/example"])
        store.save([])
        XCTAssertTrue(store.load().isEmpty)
    }
}
