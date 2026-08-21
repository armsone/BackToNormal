import Foundation

/// `ps -xo pid=,ppid=,user=,pcpu=,pmem=,rss=,state=,etime=,command=` 출력을 파싱한다.
/// 읽기 전용 명령의 텍스트 출력만 다루며 시스템 상태를 바꾸지 않는다.
public enum PsParser {

    /// ps에 넘길 출력 형식. 마지막 필드(command)만 공백을 포함할 수 있다.
    public static let outputFormat = "pid=,ppid=,user=,pcpu=,pmem=,rss=,state=,etime=,command="

    public static func parse(_ output: String) -> [ProcessSnapshot] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { parseLine(String($0)) }
    }

    /// 한 줄 파싱. 형식이 어긋나면 nil을 반환해 조용히 건너뛴다(안전한 실패).
    public static func parseLine(_ line: String) -> ProcessSnapshot? {
        let fields = line
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true)
        guard fields.count == 9 else { return nil }

        guard
            let pid = Int32(fields[0]),
            let ppid = Int32(fields[1]),
            let cpu = Double(fields[3]),
            let mem = Double(fields[4]),
            let rssKB = UInt64(fields[5])
        else { return nil }

        return ProcessSnapshot(
            pid: pid,
            ppid: ppid,
            user: String(fields[2]),
            cpuPercent: cpu,
            memPercent: mem,
            residentBytes: rssKB * 1024,
            state: String(fields[6]),
            elapsedSeconds: parseElapsedTime(String(fields[7])),
            command: String(fields[8])
        )
    }

    /// etime 형식 `[[dd-]hh:]mm:ss` 을 초 단위로 변환한다. 실패 시 nil.
    public static func parseElapsedTime(_ etime: String) -> Int? {
        var days = 0
        var rest = etime
        if let dashIndex = rest.firstIndex(of: "-") {
            guard let d = Int(rest[..<dashIndex]) else { return nil }
            days = d
            rest = String(rest[rest.index(after: dashIndex)...])
        }

        let parts = rest.split(separator: ":").map(String.init)
        guard (1...3).contains(parts.count) else { return nil }

        var seconds = 0
        for part in parts {
            guard let value = Int(part), value >= 0 else { return nil }
            let multiplied = seconds.multipliedReportingOverflow(by: 60)
            guard !multiplied.overflow else { return nil }
            let added = multiplied.partialValue.addingReportingOverflow(value)
            guard !added.overflow else { return nil }
            seconds = added.partialValue
        }
        let daySeconds = days.multipliedReportingOverflow(by: 86_400)
        guard !daySeconds.overflow else { return nil }
        let total = daySeconds.partialValue.addingReportingOverflow(seconds)
        guard !total.overflow else { return nil }
        return total.partialValue
    }
}
