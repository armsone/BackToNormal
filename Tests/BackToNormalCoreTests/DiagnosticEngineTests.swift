import XCTest
@testable import BackToNormalCore

final class DiagnosticEngineTests: XCTestCase {

    func testNoMetricsMeansScanning() {
        let diagnosis = DiagnosticEngine.evaluate(metrics: nil, processes: [])
        XCTAssertEqual(diagnosis.status, .scanning)
    }

    func testHealthySystem() {
        let diagnosis = DiagnosticEngine.evaluate(metrics: makeMetrics(), processes: [])
        XCTAssertEqual(diagnosis.status, .healthy)
        XCTAssertEqual(diagnosis.keyCause, "특이 사항 없음")
        XCTAssertTrue(diagnosis.explanation.contains("종료하지 않습니다"))
    }

    func testCriticalMemoryPressureMeansPressure() {
        let metrics = makeMetrics(memoryPressure: .critical)
        let diagnosis = DiagnosticEngine.evaluate(metrics: metrics, processes: [])
        XCTAssertEqual(diagnosis.status, .pressure)
        XCTAssertTrue(diagnosis.keyCause.contains("메모리 압박"))
    }

    func testWarningMemoryPressureMeansCaution() {
        let metrics = makeMetrics(memoryPressure: .warning)
        XCTAssertEqual(DiagnosticEngine.evaluate(metrics: metrics, processes: []).status, .caution)
    }

    func testHighLoadMeansPressure() {
        let metrics = makeMetrics(loadAverage1Min: 16.0, cpuCoreCount: 8)  // 코어당 2.0
        let diagnosis = DiagnosticEngine.evaluate(metrics: metrics, processes: [])
        XCTAssertEqual(diagnosis.status, .pressure)
        XCTAssertTrue(diagnosis.keyCause.contains("CPU"))
    }

    func testModerateLoadMeansCaution() {
        let metrics = makeMetrics(loadAverage1Min: 9.0, cpuCoreCount: 8)  // 코어당 1.125
        XCTAssertEqual(DiagnosticEngine.evaluate(metrics: metrics, processes: []).status, .caution)
    }

    func testHighSwapRatioMeansCaution() {
        let metrics = makeMetrics(swapTotal: 8 << 30, swapUsed: 5 << 30)  // 62.5%, 5 GB
        let diagnosis = DiagnosticEngine.evaluate(metrics: metrics, processes: [])
        XCTAssertEqual(diagnosis.status, .caution)
        XCTAssertTrue(diagnosis.keyCause.contains("스왑"))
    }

    func testSmallDynamicSwapDoesNotRaiseCaution() {
        let metrics = makeMetrics(swapTotal: 1 << 30, swapUsed: 700 << 20)
        XCTAssertEqual(DiagnosticEngine.evaluate(metrics: metrics, processes: []).status, .healthy)
    }

    func testUnknownPressureAloneStaysHealthy() {
        let metrics = makeMetrics(memoryPressure: .unknown)
        XCTAssertEqual(DiagnosticEngine.evaluate(metrics: metrics, processes: []).status, .healthy)
    }

    func testHeavyDevProcessMentionedAsInference() {
        let heavy = ProcessSnapshot(
            pid: 42, ppid: 100, user: "u",
            cpuPercent: 95.0, memPercent: 5.0, residentBytes: 1 << 30,
            state: "R", elapsedSeconds: 600,
            command: "/usr/bin/java org.gradle.launcher.daemon.bootstrap.GradleDaemon"
        )
        let metrics = makeMetrics(loadAverage1Min: 16.0, cpuCoreCount: 8)
        let diagnosis = DiagnosticEngine.evaluate(metrics: metrics, processes: [heavy])

        XCTAssertTrue(diagnosis.explanation.contains("추정"))
        XCTAssertTrue(diagnosis.explanation.contains("Gradle"))
        XCTAssertEqual(diagnosis.devProcesses.count, 1)
    }

    func testDeterministicOutput() {
        let metrics = makeMetrics(loadAverage1Min: 9.0, cpuCoreCount: 8)
        let first = DiagnosticEngine.evaluate(metrics: metrics, processes: [])
        let second = DiagnosticEngine.evaluate(metrics: metrics, processes: [])
        XCTAssertEqual(first, second)
    }

    func testStatusOrdering() {
        XCTAssertLessThan(SystemStatus.scanning, .healthy)
        XCTAssertLessThan(SystemStatus.healthy, .caution)
        XCTAssertLessThan(SystemStatus.caution, .pressure)
    }

    private func makeMetrics(
        loadAverage1Min: Double = 1.0,
        cpuCoreCount: Int = 8,
        memoryPressure: MemoryPressureLevel = .normal,
        swapTotal: UInt64 = 0,
        swapUsed: UInt64 = 0
    ) -> MetricsSnapshot {
        MetricsSnapshot(
            loadAverage1Min: loadAverage1Min,
            cpuCoreCount: cpuCoreCount,
            memoryPressure: memoryPressure,
            totalMemoryBytes: 32 << 30,
            availableMemoryBytes: 16 << 30,
            swapTotalBytes: swapTotal,
            swapUsedBytes: swapUsed,
            timestamp: Date(timeIntervalSince1970: 0)
        )
    }
}
