import XCTest
@testable import BackToNormalCore

final class PsParserTests: XCTestCase {

    func testConfiguredOutputFormatParsesLivePs() throws {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-xo", PsParser.outputFormat]
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        let output = try XCTUnwrap(String(data: data, encoding: .utf8))
        let snapshots = PsParser.parse(output)
        XCTAssertFalse(snapshots.isEmpty)
        XCTAssertTrue(snapshots.allSatisfy { !($0.startTimeIdentifier ?? "").isEmpty })
    }

    func testParseValidLine() throws {
        let line = "  501   1 armsone  95.3  4.2 1048576 R 01:02:03 Fri Aug 21 10:00:00 2026 /usr/bin/java -jar gradle-launcher.jar"
        let snapshot = try XCTUnwrap(PsParser.parseLine(line))
        XCTAssertEqual(snapshot.pid, 501)
        XCTAssertEqual(snapshot.ppid, 1)
        XCTAssertEqual(snapshot.user, "armsone")
        XCTAssertEqual(snapshot.cpuPercent, 95.3, accuracy: 0.001)
        XCTAssertEqual(snapshot.memPercent, 4.2, accuracy: 0.001)
        XCTAssertEqual(snapshot.residentBytes, 1_048_576 * 1024)
        XCTAssertEqual(snapshot.state, "R")
        XCTAssertEqual(snapshot.elapsedSeconds, 3723)
        XCTAssertEqual(snapshot.startTimeIdentifier, "Fri Aug 21 10:00:00 2026")
        XCTAssertEqual(snapshot.command, "/usr/bin/java -jar gradle-launcher.jar")
    }

    func testCommandKeepsInternalSpaces() throws {
        let line = "100 50 u 0.0 0.1 2048 S 00:05 Fri Aug 21 10:00:00 2026 node server.js --port 3000 --watch"
        let snapshot = try XCTUnwrap(PsParser.parseLine(line))
        XCTAssertEqual(snapshot.command, "node server.js --port 3000 --watch")
    }

    func testMalformedLineReturnsNil() {
        XCTAssertNil(PsParser.parseLine(""))
        XCTAssertNil(PsParser.parseLine("not a ps line"))
        XCTAssertNil(PsParser.parseLine("abc def ghi 0.0 0.0 100 S 00:01 Fri Aug 21 10:00:00 2026 cmd"))
    }

    func testParseMultipleLinesSkipsBadOnes() {
        let output = """
        1 0 root 0.0 0.1 1024 S 10-01:02:03 Mon Aug 10 09:00:00 2026 /sbin/launchd
        garbage line
        200 1 u 1.0 0.5 4096 S 42:10 Fri Aug 21 10:00:00 2026 node index.js
        """
        let parsed = PsParser.parse(output)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].pid, 1)
        XCTAssertEqual(parsed[1].command, "node index.js")
    }

    func testElapsedTimeFormats() {
        XCTAssertEqual(PsParser.parseElapsedTime("05"), 5)
        XCTAssertEqual(PsParser.parseElapsedTime("42:10"), 42 * 60 + 10)
        XCTAssertEqual(PsParser.parseElapsedTime("01:02:03"), 3723)
        XCTAssertEqual(PsParser.parseElapsedTime("2-01:02:03"), 2 * 86_400 + 3723)
        XCTAssertNil(PsParser.parseElapsedTime(""))
        XCTAssertNil(PsParser.parseElapsedTime("abc"))
        XCTAssertNil(PsParser.parseElapsedTime("1:2:3:4"))
        XCTAssertNil(PsParser.parseElapsedTime("999999999999999999-23:59:59"))
    }
}
