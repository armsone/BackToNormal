import XCTest
@testable import BTN
import BTNCore

final class ProcessCleanupExecutorTests: XCTestCase {
    func testLiveTerminationAdapterStopsOnlyOwnedFixture() throws {
        let fixture = Process()
        fixture.executableURL = URL(fileURLWithPath: "/bin/sleep")
        fixture.arguments = ["30"]
        try fixture.run()
        defer {
            if fixture.isRunning { fixture.terminate() }
        }

        let result = ProcessCleanupExecutor.Dependencies.live.sendTermination(fixture.processIdentifier)
        fixture.waitUntilExit()

        XCTAssertEqual(result, .sent)
        XCTAssertFalse(fixture.isRunning)
        XCTAssertNotEqual(fixture.terminationStatus, 0)
    }

    func testRevalidationFailureNeverSendsTermination() {
        var sentPIDs: [Int32] = []
        let result = ProcessCleanupExecutor.execute(candidate(), dependencies: .init(
            freshInput: { .init(processes: nil, currentUserName: "dev", ownPid: 999) },
            sendTermination: { sentPIDs.append($0); return .sent },
            isRunning: { _ in false },
            wait: { _ in }
        ))

        XCTAssertEqual(result.status, .blocked)
        XCTAssertTrue(sentPIDs.isEmpty)
    }

    func testSendsTerminationOnlyToExactCandidatePIDAndReportsExit() {
        var sentPIDs: [Int32] = []
        var checks = 0
        let target = candidate()
        let result = ProcessCleanupExecutor.execute(target, dependencies: .init(
            freshInput: { self.input(for: target) },
            sendTermination: { sentPIDs.append($0); return .sent },
            isRunning: { pid in
                XCTAssertEqual(pid, target.pid)
                checks += 1
                return checks < 2
            },
            wait: { _ in }
        ))

        XCTAssertEqual(sentPIDs, [target.pid])
        XCTAssertEqual(result.status, .cleaned)
    }

    func testSignalErrorsAreFailClosed() {
        let target = candidate()
        let cases: [(ProcessCleanupExecutor.SignalResult, CleanupExecutionStatus)] = [
            (.noSuchProcess, .blocked),
            (.notPermitted, .blocked),
            (.failed(5), .failed),
        ]

        for (signal, expected) in cases {
            var checkedExistence = false
            let result = ProcessCleanupExecutor.execute(target, dependencies: .init(
                freshInput: { self.input(for: target) },
                sendTermination: { _ in signal },
                isRunning: { _ in checkedExistence = true; return true },
                wait: { _ in }
            ))
            XCTAssertEqual(result.status, expected)
            XCTAssertFalse(checkedExistence)
        }
    }

    func testTimeoutNeverRetriesTerminationOrEscalates() {
        let target = candidate()
        var terminationCount = 0
        var waitCount = 0
        let result = ProcessCleanupExecutor.execute(target, dependencies: .init(
            freshInput: { self.input(for: target) },
            sendTermination: { _ in terminationCount += 1; return .sent },
            isRunning: { _ in true },
            wait: { _ in waitCount += 1 }
        ))

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(terminationCount, 1)
        XCTAssertEqual(waitCount, ProcessCleanupExecutor.maximumPollAttempts)
        XCTAssertTrue(result.message.contains("강제 종료(SIGKILL)를 사용하지 않으므로"))
    }

    func testLocalServerIsObservationOnlyEvenWhenFreshStateMatches() {
        let target = candidate(kind: .localServer, command: "/usr/local/bin/node webpack-dev-server")
        var didSignal = false
        let result = ProcessCleanupExecutor.execute(target, dependencies: .init(
            freshInput: { self.input(for: target) },
            sendTermination: { _ in didSignal = true; return .sent },
            isRunning: { _ in false },
            wait: { _ in }
        ))

        XCTAssertEqual(result.status, .blocked)
        XCTAssertFalse(didSignal)
    }

    private func candidate(
        kind: ProcessCleanupKind = .gradleDaemon,
        command: String = "/usr/bin/java org.gradle.launcher.daemon.bootstrap.GradleDaemon"
    ) -> ProcessCleanupCandidate {
        .init(
            id: "proc:\(kind.rawValue):500",
            kind: kind,
            pid: 500,
            ppid: 1,
            user: "dev",
            command: command,
            elapsedSeconds: 3_600,
            startTimeIdentifier: "Fri Aug 21 09:00:00 2026",
            cpuPercent: 0.2,
            residentBytes: 128 * 1024 * 1024,
            risk: kind == .localServer ? .high : .medium,
            koreanReason: "test"
        )
    }

    private func input(for target: ProcessCleanupCandidate) -> ProcessCleanupPolicyInput {
        .init(
            processes: [.init(
                pid: target.pid,
                ppid: target.ppid,
                user: target.user,
                cpuPercent: target.cpuPercent,
                memPercent: 1,
                residentBytes: target.residentBytes,
                state: "S",
                elapsedSeconds: target.elapsedSeconds + 1,
                startTimeIdentifier: target.startTimeIdentifier,
                command: target.command
            )],
            currentUserName: target.user,
            ownPid: 999
        )
    }
}
