import XCTest
@testable import BackToNormalCore

final class ProcessClassifierTests: XCTestCase {

    func testGradleDaemonDetectedBeforeGenericJava() {
        let command = "/usr/bin/java -cp gradle-launcher-8.5.jar org.gradle.launcher.daemon.bootstrap.GradleDaemon"
        XCTAssertEqual(ProcessClassifier.classify(command: command), .gradle)
    }

    func testKotlinDaemon() {
        let command = "/usr/bin/java -cp kotlin-daemon.jar org.jetbrains.kotlin.daemon.KotlinCompileDaemon"
        XCTAssertEqual(ProcessClassifier.classify(command: command), .kotlin)
    }

    func testGenericJava() {
        XCTAssertEqual(ProcessClassifier.classify(command: "/usr/bin/java -jar app.jar"), .java)
    }

    func testNodeMatchesExecutableNotArgument() {
        XCTAssertEqual(ProcessClassifier.classify(command: "/usr/local/bin/node index.js"), .node)
        XCTAssertNil(ProcessClassifier.classify(command: "vim nodejs-notes.txt"))
    }

    func testLocalServerBeforeGenericNode() {
        XCTAssertEqual(
            ProcessClassifier.classify(command: "node /project/node_modules/.bin/vite"),
            .localServer
        )
    }

    func testViteSubstringDoesNotCreateFalseLocalServerMatch() {
        XCTAssertNil(ProcessClassifier.classify(command: "/usr/bin/open invitation.txt"))
    }

    func testXcodeBuildTools() {
        XCTAssertEqual(ProcessClassifier.classify(command: "xcodebuild -scheme App build"), .xcode)
        XCTAssertEqual(
            ProcessClassifier.classify(command: "/Applications/Xcode.app/.../XCBBuildService"),
            .xcode
        )
    }

    func testTestRunner() {
        XCTAssertEqual(ProcessClassifier.classify(command: "/usr/bin/xctest MyTests.xctest"), .test)
        XCTAssertEqual(ProcessClassifier.classify(command: "node jest-worker/build/workerAdapter"), .test)
    }

    func testSimulatorAndEmulatorAndAdb() {
        XCTAssertEqual(
            ProcessClassifier.classify(command: "/Library/Developer/CoreSimulator/launchd_sim"),
            .simulator
        )
        XCTAssertEqual(
            ProcessClassifier.classify(command: "/Users/u/Library/Android/sdk/emulator/qemu-system-aarch64 -avd Pixel"),
            .emulator
        )
        XCTAssertEqual(
            ProcessClassifier.classify(command: "/Users/u/Library/Android/sdk/platform-tools/adb -L tcp:5037 fork-server server"),
            .adb
        )
    }

    func testCoreSimulatorServiceIsNotAnActiveSimulator() {
        XCTAssertNil(ProcessClassifier.classify(
            command: "/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Resources/bin/CoreSimulatorService"
        ))
    }

    func testBrowserAutomation() {
        XCTAssertEqual(ProcessClassifier.classify(command: "/opt/chromedriver --port=9515"), .browserAutomation)
        XCTAssertEqual(
            ProcessClassifier.classify(command: "Chrome --remote-debugging-port=9222"),
            .browserAutomation
        )
    }

    func testUnrelatedProcessesNotClassified() {
        XCTAssertNil(ProcessClassifier.classify(command: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"))
        XCTAssertNil(ProcessClassifier.classify(command: "/usr/sbin/mDNSResponder"))
    }

    func testClassifyAllRecordsReparentingWithoutClaimingOrphan() {
        let reparented = makeSnapshot(pid: 10, ppid: 1, command: "/usr/bin/java org.gradle.launcher.daemon.bootstrap.GradleDaemon")
        let child = makeSnapshot(pid: 11, ppid: 500, command: "node index.js")
        let results = ProcessClassifier.classifyAll([reparented, child])

        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results[0].isReparentedToLaunchd)
        XCTAssertNotNil(results[0].uncertaintyNote)  // 불확실성 명시
        XCTAssertFalse(results[1].isReparentedToLaunchd)
        XCTAssertNil(results[1].uncertaintyNote)
    }

    private func makeSnapshot(pid: Int32, ppid: Int32, command: String) -> ProcessSnapshot {
        ProcessSnapshot(
            pid: pid, ppid: ppid, user: "u",
            cpuPercent: 0, memPercent: 0, residentBytes: 0,
            state: "S", elapsedSeconds: 60, command: command
        )
    }
}
