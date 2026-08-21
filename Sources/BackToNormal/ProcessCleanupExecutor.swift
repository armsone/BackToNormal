import Foundation
import Darwin
import BackToNormalCore

struct ProcessCleanupExecutionResult: Identifiable, Sendable {
    let id = UUID()
    let candidate: ProcessCleanupCandidate
    let status: CleanupExecutionStatus
    let message: String
}

/// 실행 직전에 프로세스 스냅샷을 다시 수집·재검증한 뒤, 정확히 그 PID 하나에만
/// SIGTERM을 보낸다. SIGKILL·프로세스 그룹 시그널·데몬 중지 명령은 어떤 경우에도 쓰지 않는다.
enum ProcessCleanupExecutor {

    /// SIGTERM 후 종료를 기다리는 최대 시간. 넘기면 강제 수단 없이 실패로 보고한다.
    static let exitWaitSeconds: TimeInterval = 5

    static func execute(_ candidate: ProcessCleanupCandidate) -> ProcessCleanupExecutionResult {
        let freshInput = ProcessCleanupPolicyInput(
            processes: ProcessCollector.collectOptional(),
            currentUserName: NSUserName(),
            ownPid: ProcessInfo.processInfo.processIdentifier
        )
        let validation = ProcessCleanupRevalidation.revalidate(candidate: candidate, against: freshInput)
        guard validation.isAllowed else {
            return result(candidate, .blocked, validation.koreanReason)
        }
        // 양수 PID만 허용한다. 0·음수는 프로세스 그룹/전체 대상 시그널이 되므로 절대 보내지 않는다.
        guard candidate.pid > 1 else {
            return result(candidate, .blocked, "PID가 올바르지 않아 종료를 중단했습니다.")
        }

        guard kill(candidate.pid, SIGTERM) == 0 else {
            switch errno {
            case ESRCH:
                return result(candidate, .blocked, "프로세스가 이미 종료돼 있어 아무것도 하지 않았습니다.")
            case EPERM:
                return result(candidate, .blocked, "다른 사용자의 프로세스로 확인돼 종료하지 않았습니다.")
            default:
                return result(candidate, .failed, "SIGTERM 전송에 실패했습니다 (errno \(errno)).")
            }
        }

        let deadline = Date().addingTimeInterval(exitWaitSeconds)
        while Date() < deadline {
            usleep(200_000)
            if kill(candidate.pid, 0) == -1 && errno == ESRCH {
                return result(
                    candidate, .cleaned,
                    "SIGTERM으로 정상 종료됐습니다. 상주 메모리 약 "
                        + DiagnosticEngine.formatBytes(candidate.residentBytes)
                        + "가 회수될 것으로 예상하지만, 실제 확보량은 시스템이 결정합니다."
                )
            }
        }
        return result(
            candidate, .failed,
            "SIGTERM을 보냈지만 \(Int(exitWaitSeconds))초 안에 종료되지 않았습니다. "
                + "이 앱은 강제 종료(SIGKILL)를 사용하지 않으므로 프로세스는 그대로 남아 있습니다. "
                + "필요하면 활성 상태 보기에서 직접 확인하세요."
        )
    }

    private static func result(
        _ candidate: ProcessCleanupCandidate,
        _ status: CleanupExecutionStatus,
        _ message: String
    ) -> ProcessCleanupExecutionResult {
        ProcessCleanupExecutionResult(candidate: candidate, status: status, message: message)
    }
}
