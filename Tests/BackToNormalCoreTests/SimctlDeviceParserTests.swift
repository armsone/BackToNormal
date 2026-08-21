import XCTest
@testable import BackToNormalCore

/// 파서 테스트. 픽스처 JSON은 전부 테스트 안에서 만들며 실제 simctl을 호출하지 않는다.
final class SimctlDeviceParserTests: XCTestCase {

    private let udidA = "11111111-1111-1111-1111-111111111111"
    private let udidB = "22222222-2222-2222-2222-222222222222"

    func testFlattensDevicesAcrossMultipleRuntimes() throws {
        let json = """
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-17-0": [
              { "udid": "\(udidA)", "name": "iPhone 15", "state": "Shutdown", "isAvailable": true }
            ],
            "com.apple.CoreSimulator.SimRuntime.iOS-16-4": [
              { "udid": "\(udidB)", "name": "iPhone 14", "state": "Booted", "isAvailable": true }
            ]
          }
        }
        """
        let devices = try XCTUnwrap(SimctlDeviceParser.parse(json))

        XCTAssertEqual(devices.count, 2)
        // 런타임 키 정렬 순서 (iOS-16-4 < iOS-17-0)로 결정적이다.
        XCTAssertEqual(devices[0].name, "iPhone 14")
        XCTAssertEqual(devices[0].runtimeIdentifier, "com.apple.CoreSimulator.SimRuntime.iOS-16-4")
        XCTAssertEqual(devices[1].state, .shutdown)
    }

    func testSkipsDeviceWithInvalidOrMissingUDID() throws {
        let json = """
        {
          "devices": {
            "runtime": [
              { "udid": "not-a-uuid", "name": "깨진 기기", "state": "Shutdown", "isAvailable": true },
              { "name": "UDID 없음", "state": "Shutdown", "isAvailable": true },
              { "udid": "\(udidA)", "name": "정상 기기", "state": "Shutdown", "isAvailable": true }
            ]
          }
        }
        """
        let devices = try XCTUnwrap(SimctlDeviceParser.parse(json))

        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices[0].name, "정상 기기")
    }

    func testToleratesUnknownFieldsAndNonArrayRuntimeValues() throws {
        let json = """
        {
          "futureTopLevelKey": 42,
          "devices": {
            "brokenRuntime": "배열이 아님",
            "runtime": [
              {
                "udid": "\(udidA)",
                "name": "iPhone 15",
                "state": "Shutdown",
                "isAvailable": true,
                "dataPath": "/tmp/fixture/data",
                "dataPathSize": 123456,
                "futureDeviceKey": { "nested": true }
              }
            ]
          }
        }
        """
        let devices = try XCTUnwrap(SimctlDeviceParser.parse(json))

        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices[0].dataPath, "/tmp/fixture/data")
        XCTAssertEqual(devices[0].dataSizeBytes, 123456)
    }

    func testStateParsingMapsExactStringsOnly() {
        XCTAssertEqual(SimulatorDeviceState(rawState: "Shutdown"), .shutdown)
        XCTAssertEqual(SimulatorDeviceState(rawState: "Booted"), .booted)
        XCTAssertEqual(SimulatorDeviceState(rawState: "Creating"), .creating)
        XCTAssertEqual(SimulatorDeviceState(rawState: "Shutting Down"), .shuttingDown)
        // 대소문자·변형은 unknown으로 보존한다 (fail closed).
        XCTAssertEqual(SimulatorDeviceState(rawState: "shutdown"), .unknown("shutdown"))
        XCTAssertEqual(SimulatorDeviceState(rawState: "Rebooting"), .unknown("Rebooting"))
        XCTAssertEqual(SimulatorDeviceState(rawState: ""), .unknown(""))
    }

    func testAvailabilityParsingSupportsModernAndLegacyFormats() {
        XCTAssertEqual(SimctlDeviceParser.parseAvailability(["isAvailable": true]), true)
        XCTAssertEqual(SimctlDeviceParser.parseAvailability(["isAvailable": false]), false)
        XCTAssertEqual(SimctlDeviceParser.parseAvailability(["availability": "(available)"]), true)
        XCTAssertEqual(
            SimctlDeviceParser.parseAvailability(["availability": "(unavailable, runtime profile not found)"]),
            false
        )
        XCTAssertEqual(
            SimctlDeviceParser.parseAvailability(["availabilityError": "runtime profile not found"]),
            false
        )
        // 아무 근거도 없으면 nil (확인 불가).
        XCTAssertNil(SimctlDeviceParser.parseAvailability([:]))
    }

    func testMissingStateBecomesUnknown() throws {
        let json = """
        { "devices": { "runtime": [ { "udid": "\(udidA)", "name": "상태 없음" } ] } }
        """
        let devices = try XCTUnwrap(SimctlDeviceParser.parse(json))

        XCTAssertEqual(devices[0].state, .unknown(""))
        XCTAssertNil(devices[0].isAvailable)
    }

    func testMalformedJSONReturnsNilNotEmptyList() {
        XCTAssertNil(SimctlDeviceParser.parse("이건 JSON이 아님"))
        XCTAssertNil(SimctlDeviceParser.parse("{ \"noDevicesKey\": {} }"))
        XCTAssertNil(SimctlDeviceParser.parse("[]"))
    }

    func testEmptyDevicesMapReturnsEmptyListNotNil() throws {
        let devices = try XCTUnwrap(SimctlDeviceParser.parse("{ \"devices\": {} }"))
        XCTAssertTrue(devices.isEmpty)
    }
}
