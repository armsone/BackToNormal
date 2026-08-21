import XCTest
@testable import BackToNormalCore

final class AutomaticCleanupPolicyTests: XCTestCase {
    func testEligibilityRequiresLowRiskRecoverableUserTrashCandidate() {
        XCTAssertTrue(AutomaticCleanupPolicy.isEligible(candidate()))
        XCTAssertFalse(AutomaticCleanupPolicy.isEligible(candidate(
            kind: .ephemeralCloneSimulatorDevice,
            recovery: .notRecoverable,
            recoverable: false
        )))
        XCTAssertFalse(AutomaticCleanupPolicy.isEligible(candidate(
            risk: .medium
        )))
        // 시뮬레이터 데이터 초기화는 중간 위험·복구 불가이므로 자동 실행 대상이 아니다.
        XCTAssertFalse(AutomaticCleanupPolicy.isEligible(candidate(
            kind: .simulatorDataErase,
            risk: .medium,
            recovery: .recreatable,
            recoverable: false
        )))
        XCTAssertFalse(AutomaticCleanupPolicy.isEligible(candidate(
            kind: .simulatorDataErase
        )))
        XCTAssertFalse(AutomaticCleanupPolicy.isEligible(candidate(
            recoverable: false
        )))
        XCTAssertFalse(AutomaticCleanupPolicy.isEligible(candidate(
            recovery: .recreatable
        )))
    }

    func testPlanExcludesProtectedTargetsAndSeparatesManualOnlyCandidates() {
        let automatic = candidate(id: "auto")
        let protected = candidate(id: "protected")
        let irreversible = candidate(
            id: "simulator",
            kind: .ephemeralCloneSimulatorDevice,
            recovery: .notRecoverable,
            recoverable: false
        )
        let erase = candidate(
            id: "erase",
            kind: .simulatorDataErase,
            risk: .medium,
            recovery: .recreatable,
            recoverable: false
        )

        let plan = AutomaticCleanupPolicy.makePlan(
            candidates: [automatic, protected, irreversible, erase],
            protectedIdentifiers: ["protected"]
        )

        XCTAssertEqual(plan.targets.map(\.id), ["auto"])
        XCTAssertEqual(plan.manualOnly.map(\.id), ["simulator", "erase"])
    }

    func testNoProcessCandidateTypeCanEnterAutomaticPlan() {
        // API가 CleanupCandidate만 받으므로 ProcessCleanupCandidate를 전달할 경로 자체가 없다.
        let plan = AutomaticCleanupPolicy.makePlan(candidates: [], protectedIdentifiers: [])
        XCTAssertTrue(plan.targets.isEmpty)
        XCTAssertTrue(plan.manualOnly.isEmpty)
    }

    private func candidate(
        id: String = "derived",
        kind: CleanupCandidateKind = .derivedDataProject,
        risk: CleanupRisk = .low,
        recovery: CleanupRecoveryMethod = .userTrash,
        recoverable: Bool = true
    ) -> CleanupCandidate {
        CleanupCandidate(
            id: id,
            kind: kind,
            targetIdentifier: id,
            targetPath: "/tmp/\(id)",
            koreanReason: "test",
            estimatedBytes: 1,
            risk: risk,
            isRecoverable: recoverable,
            recoveryMethod: recovery,
            filesystemObjectIdentifier: "1:1"
        )
    }
}
