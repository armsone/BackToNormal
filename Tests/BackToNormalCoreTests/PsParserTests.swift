import XCTest
@testable import BackToNormalCore

final class PsParserTests: XCTestCase {

    func testParseValidLine() throws {
        let line = "  501   1 armsone  95.3  4.2 1048576 R 01:02:03 /usr/bin/java -jar gradle-launcher.jar"
        let snapshot = try XCTUnwrap(PsParser.parseLine(line))
        XCTAssertEqual(snapshot.pid, 501)
        XCTAssertEqual(snapshot.ppid, 1)
        XCTAssertEqual(snapshot.user, "armsone")
        XCTAssertEqual(snapshot.cpuPercent, 95.3, accuracy: 0.001)
        XCTAssertEqual(snapshot.memPercent, 4.2, accuracy: 0.001)
        XCTAssertEqual(snapshot.residentBytes, 1_048_576 * 1024)
        XCTAssertEqual(snapshot.state, "R")
        XCTAssertEqual(snapshot.elapsedSeconds, 3723)
        XCTAssertEqual(snapshot.command, "/usr/bin/java -jar gradle-launcher.jar")
    }

    func testCommandKeepsInternalSpaces() throws {
        let line = "100 50 u 0.0 0.1 2048 S 00:05 node server.js --port 3000 --watch"
        let snapshot = try XCTUnwrap(PsParser.parseLine(line))
        XCTAssertEqual(snapshot.command, "node server.js --port 3000 --watch")
    }

    func testMalformedLineReturnsNil() {
        XCTAssertNil(PsParser.parseLine(""))
        XCTAssertNil(PsParser.parseLine("not a ps line"))
        XCTAssertNil(PsParser.parseLine("abc def ghi 0.0 0.0 100 S 00:01 cmd"))
    }

    func testParseMultipleLinesSkipsBadOnes() {
        let output = """
        1 0 root 0.0 0.1 1024 S 10-01:02:03 /sbin/launchd
        garbage line
        200 1 u 1.0 0.5 4096 S 42:10 node index.js
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
