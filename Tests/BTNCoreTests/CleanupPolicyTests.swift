import XCTest
@testable import BTNCore

/// 정리 정책 테스트. 모든 관측값은 픽스처이며 실제 파일·프로세스·simctl을 건드리지 않는다.
final class CleanupPolicyTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let udidA = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let udidB = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    // MARK: - 픽스처 빌더

    private func device(
        udid: UUID? = nil,
        name: String = "iPhone 15",
        state: SimulatorDeviceState = .shutdown,
        isAvailable: Bool? = true,
        sizeBytes: UInt64? = 3 << 30
    ) -> SimulatorDevice {
        SimulatorDevice(
            udid: udid ?? udidA,
            name: name,
            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-17-0",
            state: state,
            isAvailable: isAvailable,
            dataPath: "/tmp/fixture/\(udid ?? udidA)",
            dataSizeBytes: sizeBytes
        )
    }

    private func cloneEvidence(
        udid: UUID? = nil,
        isEphemeral: Bool? = true,
        nameMarker: Bool = false
    ) -> SimulatorDevicePlistEvidence {
        SimulatorDevicePlistEvidence(
            udid: udid ?? udidA,
            isEphemeral: isEphemeral,
            hasCloneNameMarker: nameMarker
        )
    }

    private func fsEntry(
        name: String,
        ageSeconds: TimeInterval,
        sizeBytes: UInt64? = 1 << 30,
        deviceState: SimulatorDeviceState? = nil
    ) -> FilesystemCandidateEvidence {
        FilesystemCandidateEvidence(
            path: "/tmp/fixture/\(name)",
            name: name,
            modifiedAt: now.addingTimeInterval(-ageSeconds),
            sizeBytes: sizeBytes,
            deviceState: deviceState,
            filesystemObjectIdentifier: "1:2"
        )
    }

    private func idleProcesses() -> [ClassifiedProcess] { [] }

    // MARK: - 사용 불가 시뮬레이터

    func testBootedAvailableSimulatorIsProposedForSafeShutdown() {
        let candidate = CleanupPolicy.propose(CleanupPolicyInput(
            simulatorDevices: [device(state: .booted)],
            now: now
        )).first

        XCTAssertEqual(candidate?.kind, .bootedSimulatorShutdown)
        XCTAssertEqual(candidate?.id, "sim-shutdown:\(udidA.uuidString.lowercased())")
        XCTAssertEqual(candidate?.risk, .medium)
        XCTAssertTrue(candidate?.isRecoverable == true)
        XCTAssertEqual(candidate?.recoveryMethod, .restartable)
        XCTAssertEqual(candidate?.estimatedBytes, 0)
    }

    func testBootedSimulatorWithoutConfirmedAvailabilityIsNotProposed() {
        for availability in [false, nil] as [Bool?] {
            let candidates = CleanupPolicy.propose(CleanupPolicyInput(
                simulatorDevices: [device(state: .booted, isAvailable: availability)],
                now: now
            ))

            XCTAssertFalse(candidates.contains { $0.kind == .bootedSimulatorShutdown })
        }
    }

    func testUnavailableShutdownDeviceIsProposed() {
        let input = CleanupPolicyInput(
            simulatorDevices: [device(isAvailable: false)],
            now: now
        )
        let candidates = CleanupPolicy.propose(input)

        XCTAssertEqual(candidates.count, 1)
        let candidate = candidates[0]
        XCTAssertEqual(candidate.kind, .unavailableSimulatorDevice)
        XCTAssertEqual(candidate.id, "sim-unavailable:\(udidA.uuidString.lowercased())")
        XCTAssertEqual(candidate.targetIdentifier, udidA.uuidString)
        XCTAssertEqual(candidate.estimatedBytes, 3 << 30)
        XCTAssertEqual(candidate.risk, .high)
        XCTAssertFalse(candidate.isRecoverable)
        XCTAssertEqual(candidate.recoveryMethod, .notRecoverable)
        XCTAssertFalse(candidate.koreanReason.isEmpty)
    }

    func testUnknownAvailabilityIsNeverProposed() {
        let input = CleanupPolicyInput(
            simulatorDevices: [device(isAvailable: nil)],
            now: now
        )
        XCTAssertTrue(CleanupPolicy.propose(input).isEmpty)
    }

    func testUnavailableDeviceWithUnknownStateIsNotProposed() {
        let input = CleanupPolicyInput(
            simulatorDevices: [device(state: .unknown("Rebooting"), isAvailable: false)],
            now: now
        )
        XCTAssertTrue(CleanupPolicy.propose(input).isEmpty)
    }

    // MARK: - 임시(clone) 시뮬레이터

    func testShutdownCloneWithMatchingPlistEvidenceIsProposed() {
        let input = CleanupPolicyInput(
            simulatorDevices: [device(name: "Clone 1 of iPhone 15")],
            devicePlistEvidence: [cloneEvidence()],
            now: now
        )
        let candidates = CleanupPolicy.propose(input)

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].kind, .ephemeralCloneSimulatorDevice)
        XCTAssertEqual(candidates[0].id, "sim-clone:\(udidA.uuidString.lowercased())")
        XCTAssertFalse(candidates[0].isRecoverable)
        XCTAssertEqual(candidates[0].recoveryMethod, .notRecoverable)
    }

    func testCloneNameMarkerAloneIsNeverSufficientEvidence() {
        let input = CleanupPolicyInput(
            simulatorDevices: [device()],
            devicePlistEvidence: [cloneEvidence(isEphemeral: nil, nameMarker: true)],
            now: now
        )
        // 이름 표식만으로는 clone 후보가 되지 않는다. 크기가 크므로 데이터 초기화 후보만 나온다.
        XCTAssertEqual(CleanupPolicy.propose(input).map(\.kind), [.simulatorDataErase])
    }

    func testDeviceWithoutPlistEvidenceIsNeverACloneCandidate() {
        // simctl만으로는 clone을 단정할 수 없다.
        let input = CleanupPolicyInput(
            simulatorDevices: [device(name: "Clone 1 of iPhone 15")],
            devicePlistEvidence: [],
            now: now
        )
        XCTAssertEqual(CleanupPolicy.propose(input).map(\.kind), [.simulatorDataErase])
    }

    func testEvidenceWithMismatchedUDIDDoesNotApply() {
        let input = CleanupPolicyInput(
            simulatorDevices: [device(udid: udidA)],
            devicePlistEvidence: [cloneEvidence(udid: udidB)],
            now: now
        )
        XCTAssertEqual(CleanupPolicy.propose(input).map(\.kind), [.simulatorDataErase])
    }

    func testEvidenceWithoutCloneIndicatorsDoesNotApply() {
        let input = CleanupPolicyInput(
            simulatorDevices: [device()],
            devicePlistEvidence: [cloneEvidence(isEphemeral: false, nameMarker: false)],
            now: now
        )
        XCTAssertEqual(CleanupPolicy.propose(input).map(\.kind), [.simulatorDataErase])
    }

    func testNonShutdownStatesAreNeverCloneCandidates() {
        let states: [SimulatorDeviceState] = [
            .booted, .creating, .shuttingDown, .unknown("Rebooting"), .unknown(""),
        ]
        for state in states {
            let input = CleanupPolicyInput(
                simulatorDevices: [device(state: state)],
                devicePlistEvidence: [cloneEvidence()],
                now: now
            )
            let kinds = CleanupPolicy.propose(input).map(\.kind)
            XCTAssertFalse(kinds.contains(.ephemeralCloneSimulatorDevice))
            XCTAssertEqual(kinds, state == .booted ? [.bootedSimulatorShutdown] : [])
        }
    }

    func testNilSimulatorListProposesNoSimulatorCandidates() {
        // simctl 수집 실패 → fail closed.
        let input = CleanupPolicyInput(
            simulatorDevices: nil,
            devicePlistEvidence: [cloneEvidence()],
            now: now
        )
        XCTAssertTrue(CleanupPolicy.propose(input).isEmpty)
    }

    // MARK: - 시뮬레이터 데이터 초기화

    func testLargeShutdownAvailableSimulatorProposesDataErase() {
        let input = CleanupPolicyInput(
            simulatorDevices: [device(sizeBytes: 3 << 30)],
            now: now
        )
        let candidates = CleanupPolicy.propose(input)

        XCTAssertEqual(candidates.count, 1)
        let candidate = candidates[0]
        XCTAssertEqual(candidate.kind, .simulatorDataErase)
        XCTAssertEqual(candidate.id, "sim-erase:\(udidA.uuidString.lowercased())")
        XCTAssertEqual(candidate.targetIdentifier, udidA.uuidString)
        XCTAssertEqual(candidate.estimatedBytes, 3 << 30)
        XCTAssertEqual(candidate.risk, .medium)
        XCTAssertFalse(candidate.isRecoverable)
        XCTAssertEqual(candidate.recoveryMethod, .recreatable)
        XCTAssertFalse(candidate.koreanReason.isEmpty)
    }

    func testSimulatorAtExactSizeThresholdIsProposedForErase() {
        let input = CleanupPolicyInput(
            simulatorDevices: [device(sizeBytes: CleanupPolicy.simulatorDataEraseMinimumBytes)],
            now: now
        )
        XCTAssertEqual(CleanupPolicy.propose(input).map(\.kind), [.simulatorDataErase])
    }

    func testSimulatorBelowSizeThresholdIsNotProposedForErase() {
        let input = CleanupPolicyInput(
            simulatorDevices: [device(sizeBytes: CleanupPolicy.simulatorDataEraseMinimumBytes - 1)],
            now: now
        )
        XCTAssertTrue(CleanupPolicy.propose(input).isEmpty)
    }

    func testSimulatorWithUnknownSizeIsNotProposedForErase() {
        // 측정값 없음 → 크기 조건 미충족 → fail closed.
        let input = CleanupPolicyInput(
            simulatorDevices: [device(sizeBytes: nil)],
            now: now
        )
        XCTAssertTrue(CleanupPolicy.propose(input).isEmpty)
    }

    func testEphemeralCloneIsNeverProposedForDataErase() {
        // clone 증거가 있으면 삭제 후보만 나오고 초기화 후보는 나오지 않는다.
        let input = CleanupPolicyInput(
            simulatorDevices: [device(sizeBytes: 3 << 30)],
            devicePlistEvidence: [cloneEvidence()],
            now: now
        )
        XCTAssertEqual(CleanupPolicy.propose(input).map(\.kind), [.ephemeralCloneSimulatorDevice])
    }

    func testNonShutdownStatesAreNeverEraseCandidates() {
        let states: [SimulatorDeviceState] = [.creating, .shuttingDown, .unknown("Rebooting"), .unknown("")]
        for state in states {
            let input = CleanupPolicyInput(
                simulatorDevices: [device(state: state, sizeBytes: 3 << 30)],
                now: now
            )
            XCTAssertTrue(
                CleanupPolicy.propose(input).isEmpty,
                "\(state) 상태 기기는 초기화 후보가 되면 안 됨"
            )
        }
    }

    func testUnavailableOrUnknownAvailabilitySimulatorIsNeverAnEraseCandidate() {
        // 확인 불가(nil)는 아무 후보도 아니고, 사용 불가(false)는 삭제 후보 경로로만 간다.
        let unknown = CleanupPolicyInput(
            simulatorDevices: [device(isAvailable: nil, sizeBytes: 3 << 30)],
            now: now
        )
        XCTAssertTrue(CleanupPolicy.propose(unknown).isEmpty)

        let unavailable = CleanupPolicyInput(
            simulatorDevices: [device(isAvailable: false, sizeBytes: 3 << 30)],
            now: now
        )
        XCTAssertEqual(CleanupPolicy.propose(unavailable).map(\.kind), [.unavailableSimulatorDevice])
    }

    // MARK: - DerivedData

    func testOldDerivedDataProjectIsProposedWhenNoBuildActivity() {
        let input = CleanupPolicyInput(
            simulatorDevices: nil,
            derivedDataEntries: [fsEntry(name: "MyApp-abcdef", ageSeconds: 25 * 3600)],
            devProcesses: idleProcesses(),
            now: now
        )
        let candidates = CleanupPolicy.propose(input)

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].kind, .derivedDataProject)
        XCTAssertEqual(candidates[0].id, "deriveddata:MyApp-abcdef")
        XCTAssertEqual(candidates[0].targetPath, "/tmp/fixture/MyApp-abcdef")
        XCTAssertEqual(candidates[0].estimatedBytes, 1 << 30)
        XCTAssertTrue(candidates[0].isRecoverable)
        XCTAssertEqual(candidates[0].recoveryMethod, .userTrash)
    }

    func testDerivedDataYoungerThan24HoursIsNotProposed() {
        let input = CleanupPolicyInput(
            simulatorDevices: nil,
            derivedDataEntries: [fsEntry(name: "MyApp-abcdef", ageSeconds: 23 * 3600)],
            devProcesses: idleProcesses(),
            now: now
        )
        XCTAssertTrue(CleanupPolicy.propose(input).isEmpty)
    }

    func testSharedCacheDirectoriesAreExcludedRegardlessOfAge() {
        let names = [
            "ModuleCache.noindex", "CompilationCache.noindex", "SDKStatCaches.noindex",
            "SymbolCache", "Index.noindex",
        ]
        let input = CleanupPolicyInput(
            simulatorDevices: nil,
            derivedDataEntries: names.map { fsEntry(name: $0, ageSeconds: 90 * 86_400) },
            devProcesses: idleProcesses(),
            now: now
        )
        XCTAssertTrue(CleanupPolicy.propose(input).isEmpty)
    }

    func testActiveXcodeBuildProcessBlocksAllDerivedDataCandidates() {
        let build = ClassifiedProcess(
            snapshot: ProcessSnapshot(
                pid: 100, ppid: 1, user: "dev", cpuPercent: 50, memPercent: 2,
                residentBytes: 1 << 20, state: "R", elapsedSeconds: 60,
                command: "xcodebuild -scheme MyApp"
            ),
            kind: .xcode,
            isReparentedToLaunchd: false
        )
        let input = CleanupPolicyInput(
            simulatorDevices: nil,
            derivedDataEntries: [fsEntry(name: "MyApp-abcdef", ageSeconds: 48 * 3600)],
            devProcesses: [build],
            now: now
        )
        XCTAssertTrue(CleanupPolicy.propose(input).isEmpty)
    }

    func testSourceKitLanguageServerDoesNotBlockDerivedDataCandidate() {
        let languageServer = ClassifiedProcess(
            snapshot: ProcessSnapshot(
                pid: 102, ppid: 1, user: "dev", cpuPercent: 0, memPercent: 1,
                residentBytes: 1 << 20, state: "S", elapsedSeconds: 600,
                command: "/usr/bin/sourcekit-lsp"
            ),
            kind: .xcode,
            isReparentedToLaunchd: true
        )
        let input = CleanupPolicyInput(
            simulatorDevices: nil,
            derivedDataEntries: [fsEntry(name: "MyApp-abcdef", ageSeconds: 48 * 3600)],
            devProcesses: [languageServer],
            now: now
        )
        XCTAssertEqual(CleanupPolicy.propose(input).count, 1)
    }

    func testActiveTestRunnerBlocksAllDerivedDataCandidates() {
        let test = ClassifiedProcess(
            snapshot: ProcessSnapshot(
                pid: 101, ppid: 1, user: "dev", cpuPercent: 30, memPercent: 1,
                residentBytes: 1 << 20, state: "R", elapsedSeconds: 60,
                command: "xctest MyAppTests"
            ),
            kind: .test,
            isReparentedToLaunchd: false
        )
        let input = CleanupPolicyInput(
            simulatorDevices: nil,
            derivedDataEntries: [fsEntry(name: "MyApp-abcdef", ageSeconds: 48 * 3600)],
            devProcesses: [test],
            now: now
        )
        XCTAssertTrue(CleanupPolicy.propose(input).isEmpty)
    }

    func testUnknownProcessListBlocksDerivedDataCandidates() {
        // 프로세스 목록 수집 실패 → 빌드 활동 여부 미상 → fail closed.
        let input = CleanupPolicyInput(
            simulatorDevices: nil,
            derivedDataEntries: [fsEntry(name: "MyApp-abcdef", ageSeconds: 48 * 3600)],
            devProcesses: nil,
            now: now
        )
        XCTAssertTrue(CleanupPolicy.propose(input).isEmpty)
    }

    func testDerivedDataWithUnknownModificationDateIsNotProposed() {
        let entry = FilesystemCandidateEvidence(
            path: "/tmp/fixture/MyApp-abcdef",
            name: "MyApp-abcdef",
            modifiedAt: nil,
            sizeBytes: 1 << 30
        )
        let input = CleanupPolicyInput(
            simulatorDevices: nil,
            derivedDataEntries: [entry],
            devProcesses: idleProcesses(),
            now: now
        )
        XCTAssertTrue(CleanupPolicy.propose(input).isEmpty)
    }

    func testDerivedDataWithoutFilesystemIdentifierIsNotProposed() {
        let entry = FilesystemCandidateEvidence(
            path: "/tmp/fixture/MyApp-abcdef",
            name: "MyApp-abcdef",
            modifiedAt: now.addingTimeInterval(-48 * 3600),
            sizeBytes: 1 << 30
        )
        let input = CleanupPolicyInput(
            simulatorDevices: nil,
            derivedDataEntries: [entry],
            devProcesses: [],
            now: now
        )
        XCTAssertTrue(CleanupPolicy.propose(input).isEmpty)
    }

    // MARK: - XCTestDevices

    func testOldShutdownXCTestDeviceDirectoryIsProposed() {
        let input = CleanupPolicyInput(
            simulatorDevices: nil,
            xctestDeviceEntries: [
                fsEntry(name: udidB.uuidString, ageSeconds: 8 * 86_400, deviceState: .shutdown)
            ],
            now: now
        )
        let candidates = CleanupPolicy.propose(input)

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].kind, .xctestDeviceDirectory)
        XCTAssertEqual(candidates[0].risk, .medium)
        XCTAssertEqual(candidates[0].recoveryMethod, .userTrash)
    }

    func testXCTestDeviceYoungerThan7DaysIsNotProposed() {
        let input = CleanupPolicyInput(
            simulatorDevices: nil,
            xctestDeviceEntries: [
                fsEntry(name: udidB.uuidString, ageSeconds: 6 * 86_400, deviceState: .shutdown)
            ],
            now: now
        )
        XCTAssertTrue(CleanupPolicy.propose(input).isEmpty)
    }

    func testXCTestDeviceWithoutExplicitShutdownStateIsNotProposed() {
        let states: [SimulatorDeviceState?] = [nil, .booted, .unknown("Rebooting")]
        for state in states {
            let input = CleanupPolicyInput(
                simulatorDevices: nil,
                xctestDeviceEntries: [
                    fsEntry(name: udidB.uuidString, ageSeconds: 30 * 86_400, deviceState: state)
                ],
                now: now
            )
            XCTAssertTrue(CleanupPolicy.propose(input).isEmpty, "\(String(describing: state)) 상태는 제외돼야 함")
        }
    }

    // MARK: - 공통 성질

    func testProposalIsDeterministicAndStablyOrdered() {
        let input = CleanupPolicyInput(
            simulatorDevices: [
                device(udid: udidB, isAvailable: false),
                device(udid: udidA),
            ],
            devicePlistEvidence: [cloneEvidence(udid: udidA)],
            derivedDataEntries: [
                fsEntry(name: "Zeta-xyz", ageSeconds: 48 * 3600),
                fsEntry(name: "Alpha-abc", ageSeconds: 48 * 3600),
            ],
            xctestDeviceEntries: [
                fsEntry(name: "33333333-3333-3333-3333-333333333333", ageSeconds: 10 * 86_400, deviceState: .shutdown)
            ],
            devProcesses: idleProcesses(),
            now: now
        )
        let first = CleanupPolicy.propose(input)
        let second = CleanupPolicy.propose(input)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.map(\.id), [
            "deriveddata:Alpha-abc",
            "deriveddata:Zeta-xyz",
            "sim-clone:\(udidA.uuidString.lowercased())",
            "sim-unavailable:\(udidB.uuidString.lowercased())",
            "xctest:33333333-3333-3333-3333-333333333333",
        ])
    }

    func testMissingSizeMeasurementFallsBackToZeroEstimate() {
        let input = CleanupPolicyInput(
            simulatorDevices: [device(isAvailable: false, sizeBytes: nil)],
            now: now
        )
        XCTAssertEqual(CleanupPolicy.propose(input).first?.estimatedBytes, 0)
    }

    func testEmptyInputProposesNothing() {
        let input = CleanupPolicyInput(
            simulatorDevices: [],
            derivedDataEntries: [],
            xctestDeviceEntries: [],
            devProcesses: [],
            now: now
        )
        XCTAssertTrue(CleanupPolicy.propose(input).isEmpty)
    }

    func testNoCandidateEverTargetsAProcess() {
        // 이 정책은 프로세스 후보를 만들지 않는다. 프로세스 정리는 별도 타입과 정책을 사용한다.
        for kind in CleanupCandidateKind.allCases {
            XCTAssertFalse(kind.rawValue.lowercased().contains("process"))
        }
    }
}
