import XCTest
@testable import BackToNormalCore

final class ProcessCleanupPolicyTests: XCTestCase {
    private let currentUser = "dev"
    private let gradleCommand = "/usr/bin/java org.gradle.launcher.daemon.bootstrap.GradleDaemon"

    func testProposesOnlyEligibleAllowlistedProcess() {
        let candidates = propose([snapshot()])

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.kind, .gradleDaemon)
        XCTAssertEqual(candidates.first?.pid, 500)
        XCTAssertEqual(candidates.first?.risk, .medium)
        XCTAssertEqual(candidates.first?.residentBytes, 128 * 1024 * 1024)
    }

    func testFailsClosedWhenProcessCollectionOrUserIsUnavailable() {
        XCTAssertTrue(ProcessCleanupPolicy.propose(.init(
            processes: nil, currentUserName: currentUser, ownPid: 999
        )).isEmpty)
        XCTAssertTrue(ProcessCleanupPolicy.propose(.init(
            processes: [snapshot()], currentUserName: nil, ownPid: 999
        )).isEmpty)
        XCTAssertTrue(ProcessCleanupPolicy.propose(.init(
            processes: [snapshot()], currentUserName: "", ownPid: 999
        )).isEmpty)
    }

    func testExcludesAmbiguousAndProtectedProcessKinds() {
        let commands = [
            "/usr/bin/java -jar app.jar",
            "/usr/local/bin/node server.js",
            "/usr/bin/xcodebuild test",
            "/Applications/Xcode.app/Contents/Developer/usr/bin/simctl list",
            "/opt/android-sdk/emulator/emulator -avd Pixel",
            "/opt/android-sdk/platform-tools/adb devices",
            "./gradlew assembleDebug",
        ]

        XCTAssertTrue(ProcessCleanupPolicy.propose(.init(
            processes: commands.enumerated().map { index, command in
                snapshot(pid: Int32(600 + index), command: command)
            },
            currentUserName: currentUser,
            ownPid: 999
        )).isEmpty)
    }

    func testRejectsAnyFailedSafetyCondition() {
        let invalid = [
            snapshot(pid: 1),
            snapshot(pid: 999),
            snapshot(ppid: 42),
            snapshot(user: "someone-else"),
            snapshot(cpu: 1.01),
            snapshot(cpu: -0.1),
            snapshot(cpu: .nan),
            snapshot(cpu: .infinity),
            snapshot(rss: 64 * 1024 * 1024 - 1),
            snapshot(state: "R+"),
            snapshot(state: "Z"),
            snapshot(state: "T"),
            snapshot(state: "U"),
            snapshot(state: ""),
            snapshot(elapsed: ProcessCleanupPolicy.minimumElapsedSeconds - 1),
            snapshot(elapsed: nil),
            snapshot(startTimeIdentifier: nil),
            snapshot(startTimeIdentifier: ""),
        ]

        for process in invalid {
            XCTAssertTrue(propose([process]).isEmpty, "unexpected candidate: \(process)")
        }
    }

    func testRecognizesEachExplicitAllowlistedKind() {
        let cases: [(String, ProcessCleanupKind, CleanupRisk)] = [
            (gradleCommand, .gradleDaemon, .medium),
            ("/usr/bin/java org.jetbrains.kotlin.daemon.KotlinCompileDaemon", .kotlinDaemon, .medium),
            ("/usr/bin/python3 -m pytest", .testRunner, .medium),
            ("/usr/local/bin/chromedriver --port=9515", .browserAutomation, .medium),
            ("/usr/local/bin/node webpack-dev-server", .localServer, .high),
        ]

        for (index, item) in cases.enumerated() {
            let candidate = propose([snapshot(pid: Int32(700 + index), command: item.0)]).first
            XCTAssertEqual(candidate?.kind, item.1)
            XCTAssertEqual(candidate?.risk, item.2)
            XCTAssertEqual(candidate?.isActionable, item.1 != .localServer)
        }
    }

    func testProposalOrderingIsDeterministic() {
        let processes = [
            snapshot(pid: 900, command: "/usr/bin/python3 -m pytest"),
            snapshot(pid: 800, command: gradleCommand),
            snapshot(pid: 700, command: gradleCommand),
        ]

        XCTAssertEqual(propose(processes).map(\.pid), [700, 800, 900])
    }

    func testRevalidationAllowsUnchangedOlderCandidate() {
        let candidate = propose([snapshot(elapsed: 3_600)]).first!
        let result = ProcessCleanupRevalidation.revalidate(
            candidate: candidate,
            against: input([snapshot(elapsed: 3_601)])
        )

        XCTAssertTrue(result.isAllowed)
    }

    func testRevalidationBlocksChangedOrNewlyIneligibleProcess() {
        let candidate = propose([snapshot(elapsed: 3_600)]).first!
        let changedSnapshots = [
            snapshot(ppid: 2, elapsed: 3_601),
            snapshot(user: "other", elapsed: 3_601),
            snapshot(cpu: 2, elapsed: 3_601),
            snapshot(elapsed: 3_599),
            snapshot(elapsed: 3_601, startTimeIdentifier: "Fri Aug 21 10:00:00 2026"),
            snapshot(elapsed: 3_601, command: "/usr/bin/python3 -m pytest"),
            snapshot(elapsed: 3_601, command: gradleCommand + " --changed"),
        ]

        for process in changedSnapshots {
            let result = ProcessCleanupRevalidation.revalidate(
                candidate: candidate,
                against: input([process])
            )
            XCTAssertFalse(result.isAllowed, "unexpectedly allowed: \(process)")
        }
        XCTAssertFalse(ProcessCleanupRevalidation.revalidate(
            candidate: candidate,
            against: .init(processes: nil, currentUserName: currentUser, ownPid: 999)
        ).isAllowed)
    }

    func testExpectedResidentBytesUsesSaturatingSum() {
        let first = candidate(residentBytes: UInt64.max - 5)
        let second = candidate(pid: 501, residentBytes: 10)

        XCTAssertEqual(
            ProcessCleanupPolicy.totalExpectedResidentBytes(of: [first, second]),
            UInt64.max
        )
    }

    func testProtectionIdentifierDoesNotDependOnReusablePID() {
        let first = candidate(pid: 500, residentBytes: 128 * 1024 * 1024)
        let second = candidate(pid: 999, residentBytes: 128 * 1024 * 1024)

        XCTAssertEqual(first.protectionIdentifier, second.protectionIdentifier)
        XCTAssertFalse(first.protectionIdentifier.contains(":500"))
    }

    private func propose(_ processes: [ProcessSnapshot]) -> [ProcessCleanupCandidate] {
        ProcessCleanupPolicy.propose(input(processes))
    }

    private func input(_ processes: [ProcessSnapshot]) -> ProcessCleanupPolicyInput {
        .init(processes: processes, currentUserName: currentUser, ownPid: 999)
    }

    private func snapshot(
        pid: Int32 = 500,
        ppid: Int32 = 1,
        user: String = "dev",
        cpu: Double = 0.2,
        rss: UInt64 = 128 * 1024 * 1024,
        state: String = "S",
        elapsed: Int? = 3_600,
        startTimeIdentifier: String? = "Fri Aug 21 09:00:00 2026",
        command: String? = nil
    ) -> ProcessSnapshot {
        .init(
            pid: pid,
            ppid: ppid,
            user: user,
            cpuPercent: cpu,
            memPercent: 1,
            residentBytes: rss,
            state: state,
            elapsedSeconds: elapsed,
            startTimeIdentifier: startTimeIdentifier,
            command: command ?? gradleCommand
        )
    }

    private func candidate(pid: Int32 = 500, residentBytes: UInt64) -> ProcessCleanupCandidate {
        .init(
            id: "proc:gradleDaemon:\(pid)",
            kind: .gradleDaemon,
            pid: pid,
            ppid: 1,
            user: currentUser,
            command: gradleCommand,
            elapsedSeconds: 3_600,
            startTimeIdentifier: "Fri Aug 21 09:00:00 2026",
            cpuPercent: 0.2,
            residentBytes: residentBytes,
            risk: .medium,
            koreanReason: "test"
        )
    }
}
