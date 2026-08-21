import XCTest
@testable import BackToNormalCore

/// 실행 직전 재검증 테스트. 순수 함수만 검증하며 아무것도 실행하지 않는다.
final class CleanupRevalidationTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let udid = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    private func cloneInput(
        state: SimulatorDeviceState = .shutdown,
        withEvidence: Bool = true
    ) -> CleanupPolicyInput {
        CleanupPolicyInput(
            simulatorDevices: [
                SimulatorDevice(
                    udid: udid,
                    name: "Clone 1 of iPhone 15",
                    runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-17-0",
                    state: state,
                    isAvailable: true,
                    dataPath: "/tmp/fixture/\(udid)"
                )
            ],
            devicePlistEvidence: withEvidence
                ? [SimulatorDevicePlistEvidence(udid: udid, isEphemeral: true, hasCloneNameMarker: true)]
                : [],
            now: now
        )
    }

    private func eraseInput(
        state: SimulatorDeviceState = .shutdown,
        isAvailable: Bool? = true,
        sizeBytes: UInt64? = 2 << 30
    ) -> CleanupPolicyInput {
        CleanupPolicyInput(
            simulatorDevices: [
                SimulatorDevice(
                    udid: udid,
                    name: "iPhone 15",
                    runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-17-0",
                    state: state,
                    isAvailable: isAvailable,
                    dataPath: "/tmp/fixture/\(udid)",
                    dataSizeBytes: sizeBytes
                )
            ],
            now: now
        )
    }

    private func shutdownInput(state: SimulatorDeviceState = .booted) -> CleanupPolicyInput {
        CleanupPolicyInput(
            simulatorDevices: [
                SimulatorDevice(
                    udid: udid,
                    name: "iPhone 15",
                    runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-17-0",
                    state: state,
                    isAvailable: true,
                    dataPath: "/tmp/fixture/\(udid)"
                )
            ],
            now: now
        )
    }

    private func derivedDataInput(
        ageSeconds: TimeInterval,
        devProcesses: [ClassifiedProcess]? = [],
        filesystemObjectIdentifier: String = "1:2"
    ) -> CleanupPolicyInput {
        CleanupPolicyInput(
            simulatorDevices: nil,
            derivedDataEntries: [
                FilesystemCandidateEvidence(
                    path: "/tmp/fixture/MyApp-abcdef",
                    name: "MyApp-abcdef",
                    modifiedAt: now.addingTimeInterval(-ageSeconds),
                    sizeBytes: 1 << 30,
                    filesystemObjectIdentifier: filesystemObjectIdentifier
                )
            ],
            devProcesses: devProcesses,
            now: now
        )
    }

    func testUnchangedEvidenceAllowsCandidate() throws {
        let input = cloneInput()
        let candidate = try XCTUnwrap(CleanupPolicy.propose(input).first)

        let result = CleanupRevalidation.revalidate(candidate: candidate, against: input)

        XCTAssertTrue(result.isAllowed)
        XCTAssertFalse(result.koreanReason.isEmpty)
    }

    func testDeviceBootedSinceProposalBlocksCandidate() throws {
        let candidate = try XCTUnwrap(CleanupPolicy.propose(cloneInput()).first)

        let result = CleanupRevalidation.revalidate(
            candidate: candidate,
            against: cloneInput(state: .booted)
        )

        XCTAssertFalse(result.isAllowed)
        XCTAssertFalse(result.koreanReason.isEmpty)
    }

    func testEvidenceDisappearanceBlocksCandidate() throws {
        let candidate = try XCTUnwrap(CleanupPolicy.propose(cloneInput()).first)

        let result = CleanupRevalidation.revalidate(
            candidate: candidate,
            against: cloneInput(withEvidence: false)
        )

        XCTAssertFalse(result.isAllowed)
    }

    func testFreshCollectionFailureBlocksCandidate() throws {
        let candidate = try XCTUnwrap(CleanupPolicy.propose(cloneInput()).first)
        let failedInput = CleanupPolicyInput(simulatorDevices: nil, now: now)

        let result = CleanupRevalidation.revalidate(candidate: candidate, against: failedInput)

        XCTAssertFalse(result.isAllowed)
    }

    func testUnchangedBootedSimulatorAllowsShutdownCandidate() throws {
        let input = shutdownInput()
        let candidate = try XCTUnwrap(CleanupPolicy.propose(input).first)

        XCTAssertEqual(candidate.kind, .bootedSimulatorShutdown)
        XCTAssertTrue(CleanupRevalidation.revalidate(candidate: candidate, against: input).isAllowed)
    }

    func testAlreadyShutdownSimulatorBlocksShutdownCandidate() throws {
        let candidate = try XCTUnwrap(CleanupPolicy.propose(shutdownInput()).first)

        XCTAssertFalse(CleanupRevalidation.revalidate(
            candidate: candidate,
            against: shutdownInput(state: .shutdown)
        ).isAllowed)
    }

    func testUnchangedEraseEvidenceAllowsCandidate() throws {
        let input = eraseInput()
        let candidate = try XCTUnwrap(CleanupPolicy.propose(input).first)
        XCTAssertEqual(candidate.kind, .simulatorDataErase)

        let result = CleanupRevalidation.revalidate(candidate: candidate, against: input)

        XCTAssertTrue(result.isAllowed)
    }

    func testDeviceBootedSinceProposalBlocksEraseCandidate() throws {
        let candidate = try XCTUnwrap(CleanupPolicy.propose(eraseInput()).first)

        let result = CleanupRevalidation.revalidate(
            candidate: candidate,
            against: eraseInput(state: .booted)
        )

        XCTAssertFalse(result.isAllowed)
    }

    func testSizeDroppedBelowThresholdBlocksEraseCandidate() throws {
        let candidate = try XCTUnwrap(CleanupPolicy.propose(eraseInput()).first)

        // 그 사이 데이터가 지워져 크기 조건이 더 이상 성립하지 않으면 실행하지 않는다.
        let result = CleanupRevalidation.revalidate(
            candidate: candidate,
            against: eraseInput(sizeBytes: 1 << 20)
        )

        XCTAssertFalse(result.isAllowed)
    }

    func testAvailabilityLostSinceProposalBlocksEraseCandidate() throws {
        let candidate = try XCTUnwrap(CleanupPolicy.propose(eraseInput()).first)

        let result = CleanupRevalidation.revalidate(
            candidate: candidate,
            against: eraseInput(isAvailable: false)
        )

        XCTAssertFalse(result.isAllowed)
    }

    func testFreshCollectionFailureBlocksEraseCandidate() throws {
        let candidate = try XCTUnwrap(CleanupPolicy.propose(eraseInput()).first)
        let failedInput = CleanupPolicyInput(simulatorDevices: nil, now: now)

        let result = CleanupRevalidation.revalidate(candidate: candidate, against: failedInput)

        XCTAssertFalse(result.isAllowed)
    }

    func testRecentlyModifiedDerivedDataBlocksCandidate() throws {
        let candidate = try XCTUnwrap(
            CleanupPolicy.propose(derivedDataInput(ageSeconds: 48 * 3600)).first
        )

        // 재검증 시점엔 10분 전에 수정됨 — 빌드가 다시 쓰고 있을 수 있다.
        let result = CleanupRevalidation.revalidate(
            candidate: candidate,
            against: derivedDataInput(ageSeconds: 600)
        )

        XCTAssertFalse(result.isAllowed)
    }

    func testNewBuildActivityBlocksDerivedDataCandidate() throws {
        let candidate = try XCTUnwrap(
            CleanupPolicy.propose(derivedDataInput(ageSeconds: 48 * 3600)).first
        )
        let build = ClassifiedProcess(
            snapshot: ProcessSnapshot(
                pid: 200, ppid: 1, user: "dev", cpuPercent: 90, memPercent: 3,
                residentBytes: 1 << 20, state: "R", elapsedSeconds: 5,
                command: "xcodebuild -scheme MyApp"
            ),
            kind: .xcode,
            isReparentedToLaunchd: false
        )

        let result = CleanupRevalidation.revalidate(
            candidate: candidate,
            against: derivedDataInput(ageSeconds: 48 * 3600, devProcesses: [build])
        )

        XCTAssertFalse(result.isAllowed)
    }

    func testBatchRevalidationPreservesOrderAndJudgesEachCandidate() throws {
        let input = cloneInput()
        let candidates = CleanupPolicy.propose(input)
        XCTAssertEqual(candidates.count, 1)

        let results = CleanupRevalidation.revalidate(candidates: candidates, against: input)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].candidate, candidates[0])
        XCTAssertTrue(results[0].result.isAllowed)
    }

    func testCandidateWithTamperedPathIsBlocked() throws {
        let input = derivedDataInput(ageSeconds: 48 * 3600)
        var candidate = try XCTUnwrap(CleanupPolicy.propose(input).first)
        candidate.targetPath = "/tmp/fixture/다른-경로"

        let result = CleanupRevalidation.revalidate(candidate: candidate, against: input)

        XCTAssertFalse(result.isAllowed)
    }

    func testReplacedFilesystemObjectIsBlocked() throws {
        let original = derivedDataInput(ageSeconds: 48 * 3600)
        let candidate = try XCTUnwrap(CleanupPolicy.propose(original).first)

        let result = CleanupRevalidation.revalidate(
            candidate: candidate,
            against: derivedDataInput(
                ageSeconds: 48 * 3600,
                filesystemObjectIdentifier: "1:999"
            )
        )

        XCTAssertFalse(result.isAllowed)
    }
}
