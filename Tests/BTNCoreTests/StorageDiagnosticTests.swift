import XCTest
@testable import BTNCore

final class StorageDiagnosticTests: XCTestCase {
    func testLargeSimulatorFootprintRaisesCautionAndExplainsCause() {
        let diagnosis = DiagnosticEngine.evaluate(
            metrics: normalMetrics(),
            processes: [],
            storage: storage(simulatorCount: 12, simulatorBytes: 29 << 30)
        )

        XCTAssertEqual(diagnosis.status, .caution)
        XCTAssertTrue(diagnosis.keyCause.contains("시뮬레이터"))
        XCTAssertEqual(diagnosis.storageFindings.count, 1)
    }

    func testManyEphemeralSimulatorClonesRaisePressure() {
        let diagnosis = DiagnosticEngine.evaluate(
            metrics: normalMetrics(),
            processes: [],
            storage: storage(simulatorCount: 40, ephemeralCount: 12)
        )

        XCTAssertEqual(diagnosis.status, .pressure)
        XCTAssertTrue(diagnosis.storageFindings.contains { $0.contains("임시 시뮬레이터") })
    }

    func testLowDiskSpaceRaisesPressure() {
        let diagnosis = DiagnosticEngine.evaluate(
            metrics: normalMetrics(),
            processes: [],
            storage: storage(availableBytes: 30 << 30)
        )

        XCTAssertEqual(diagnosis.status, .pressure)
        XCTAssertTrue(diagnosis.keyCause.contains("디스크 여유"))
    }

    func testSmallDeveloperFootprintRemainsHealthy() {
        let diagnosis = DiagnosticEngine.evaluate(
            metrics: normalMetrics(),
            processes: [],
            storage: storage(simulatorCount: 5, simulatorBytes: 5 << 30, derivedDataBytes: 4 << 30)
        )

        XCTAssertEqual(diagnosis.status, .healthy)
        XCTAssertTrue(diagnosis.storageFindings.isEmpty)
    }

    func testUnknownVolumeCapacityDoesNotCreateFalseLowDiskAlert() {
        let diagnosis = DiagnosticEngine.evaluate(
            metrics: normalMetrics(),
            processes: [],
            storage: StorageSnapshot(
                volumeTotalBytes: 0,
                volumeAvailableBytes: 0,
                simulatorDeviceCount: 0,
                ephemeralSimulatorCount: 0,
                simulatorBytes: 0,
                derivedDataBytes: 0,
                xctestDeviceBytes: 0
            )
        )

        XCTAssertEqual(diagnosis.status, .healthy)
    }

    private func normalMetrics() -> MetricsSnapshot {
        MetricsSnapshot(
            loadAverage1Min: 1,
            cpuCoreCount: 8,
            memoryPressure: .normal,
            totalMemoryBytes: 32 << 30,
            availableMemoryBytes: 16 << 30,
            swapTotalBytes: 0,
            swapUsedBytes: 0,
            timestamp: Date(timeIntervalSince1970: 0)
        )
    }

    private func storage(
        availableBytes: UInt64 = 300 << 30,
        simulatorCount: Int = 5,
        ephemeralCount: Int = 0,
        simulatorBytes: UInt64 = 5 << 30,
        derivedDataBytes: UInt64 = 4 << 30
    ) -> StorageSnapshot {
        StorageSnapshot(
            volumeTotalBytes: 1 << 40,
            volumeAvailableBytes: availableBytes,
            simulatorDeviceCount: simulatorCount,
            ephemeralSimulatorCount: ephemeralCount,
            simulatorBytes: simulatorBytes,
            derivedDataBytes: derivedDataBytes,
            xctestDeviceBytes: 0,
            timestamp: Date(timeIntervalSince1970: 0)
        )
    }
}
