import SwiftUI
import BackToNormalCore

/// 상세 창: 지표, 진단 설명, 개발 관련 프로세스 목록.
struct DetailView: View {
    @ObservedObject var model: MonitorViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                metricsSection
                storageSection
                cleanupSection
                explanationSection
                processSection
            }
            .padding(16)
        }
        .sheet(isPresented: $model.isShowingCleanupConfirmation) {
            CleanupConfirmationView(model: model)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    model.refresh()
                } label: {
                    Label("새로고침", systemImage: "arrow.clockwise")
                }
                .disabled(model.isRefreshing)
            }
        }
    }

    @ViewBuilder
    private var storageSection: some View {
        if let storage = model.storage {
            GroupBox("개발 저장 공간") {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 4) {
                    GridRow {
                        Text("디스크 여유")
                        Text(storage.volumeTotalBytes > 0
                             ? DiagnosticEngine.formatBytes(storage.volumeAvailableBytes)
                             : "확인 불가")
                    }
                    GridRow {
                        Text("시뮬레이터")
                        Text("\(storage.simulatorDeviceCount)개 · \(DiagnosticEngine.formatBytes(storage.simulatorBytes))")
                    }
                    if storage.ephemeralSimulatorCount > 0 {
                        GridRow {
                            Text("테스트 복제본 의심")
                            Text("\(storage.ephemeralSimulatorCount)개")
                                .foregroundStyle(.orange)
                        }
                    }
                    GridRow {
                        Text("Xcode DerivedData")
                        Text(DiagnosticEngine.formatBytes(storage.derivedDataBytes))
                    }
                    if storage.xctestDeviceBytes > 0 {
                        GridRow {
                            Text("XCTest 기기 데이터")
                            Text(DiagnosticEngine.formatBytes(storage.xctestDeviceBytes))
                        }
                    }
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: model.statusSymbolName)
                .font(.title)
                .foregroundStyle(model.statusColor)
            VStack(alignment: .leading) {
                Text("상태: \(model.diagnosis.status.koreanLabel)")
                    .font(.title2.bold())
                Text(model.diagnosis.keyCause)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("권장 모드")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
        }
    }

    private var cleanupSection: some View {
        GroupBox("안전한 원상복구") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("후보는 자동 선택되지 않으며, 실행 직전에 다시 확인합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        model.scanCleanupCandidates()
                    } label: {
                        Label(
                            model.isScanningCleanup ? "찾는 중" : "정리 후보 찾기",
                            systemImage: "magnifyingglass"
                        )
                    }
                    .disabled(model.isScanningCleanup || model.isCleaning)
                }

                if model.isScanningCleanup {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if model.cleanupCandidates.isEmpty && model.processCleanupCandidates.isEmpty {
                    Text("버튼을 눌러 오래된 DerivedData, XCTest 데이터, 종료된 테스트 시뮬레이터와 방치된 것으로 보이는 개발 프로세스를 확인하세요.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    if !model.cleanupCandidates.isEmpty {
                        Text("디스크 공간 확보")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        VStack(spacing: 6) {
                            ForEach(model.cleanupCandidates) { candidate in
                                CleanupCandidateRow(
                                    candidate: candidate,
                                    isSelected: model.selectedCleanupIDs.contains(candidate.id),
                                    toggle: { model.toggleCleanupCandidate(candidate) }
                                )
                            }
                        }
                    }

                    if !model.processCleanupCandidates.isEmpty {
                        Text("메모리 확보 (프로세스 종료 — 되돌릴 수 없음)")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        VStack(spacing: 6) {
                            ForEach(model.processCleanupCandidates) { candidate in
                                ProcessCleanupCandidateRow(
                                    candidate: candidate,
                                    isSelected: model.selectedProcessCleanupIDs.contains(candidate.id),
                                    toggle: { model.toggleProcessCleanupCandidate(candidate) }
                                )
                            }
                        }
                    }

                    HStack {
                        // 디스크와 메모리는 성격이 다른 예상치이므로 절대 하나로 합산하지 않는다.
                        VStack(alignment: .leading, spacing: 2) {
                            Text("디스크: \(model.selectedCandidates.count)개 선택 · 최대 \(DiagnosticEngine.formatBytes(model.selectedCleanupBytes))")
                            Text("메모리: \(model.selectedProcessCandidates.count)개 선택 · 상주 메모리 약 \(DiagnosticEngine.formatBytes(model.selectedProcessMemoryBytes))")
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        Spacer()
                        Button("선택 항목 정리…") {
                            model.requestCleanupConfirmation()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled((model.selectedCandidates.isEmpty && model.selectedProcessCandidates.isEmpty) || model.isCleaning)
                    }
                }

                if model.isCleaning {
                    ProgressView("항목마다 안전 조건을 다시 확인하고 있습니다…")
                }

                ForEach(model.cleanupResults) { result in
                    CleanupResultLabel(
                        status: result.status,
                        title: "\(result.status.koreanLabel): \(result.candidate.targetIdentifier)",
                        message: result.message
                    )
                }

                ForEach(model.processCleanupResults) { result in
                    CleanupResultLabel(
                        status: result.status,
                        title: "\(result.status.koreanLabel): \(result.candidate.kind.koreanLabel) (pid \(result.candidate.pid))",
                        message: result.message
                    )
                }
            }
            .padding(4)
        }
    }

    @ViewBuilder
    private var metricsSection: some View {
        if let metrics = model.metrics {
            GroupBox("측정값") {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 4) {
                    GridRow {
                        Text("CPU 부하 (1분)")
                        Text(String(format: "%.2f / 코어 %d개 (코어당 %.2f)",
                                    metrics.loadAverage1Min,
                                    metrics.cpuCoreCount,
                                    metrics.normalizedLoad))
                    }
                    GridRow {
                        Text("메모리 압박")
                        Text(metrics.memoryPressure.koreanLabel)
                    }
                    GridRow {
                        Text("사용 가능 메모리")
                        Text(metrics.availableMemoryBytes.map { DiagnosticEngine.formatBytes($0) } ?? "확인 불가")
                    }
                    GridRow {
                        Text("스왑 사용")
                        Text("\(DiagnosticEngine.formatBytes(metrics.swapUsedBytes)) / \(DiagnosticEngine.formatBytes(metrics.swapTotalBytes))")
                    }
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
        }
    }

    private var explanationSection: some View {
        GroupBox("진단") {
            Text(model.diagnosis.explanation)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
        }
    }

    private var processSection: some View {
        GroupBox("개발 관련 프로세스 (\(model.diagnosis.devProcesses.count)개)") {
            if model.diagnosis.devProcesses.isEmpty {
                Text("감지된 개발 관련 프로세스가 없습니다.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
            } else {
                List(model.diagnosis.devProcesses) { process in
                    ProcessRow(process: process)
                }
                .listStyle(.inset)
                .frame(minHeight: 160)
            }
        }
    }
}

private struct CleanupCandidateRow: View {
    let candidate: CleanupCandidate
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(candidate.kind.koreanLabel).bold()
                        Text(candidate.targetIdentifier)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(DiagnosticEngine.formatBytes(candidate.estimatedBytes))
                            .monospacedDigit()
                    }
                    Text(candidate.koreanReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text("위험도 \(candidate.risk.koreanLabel)")
                        Text("·")
                        Text(candidate.recoveryMethod.koreanLabel)
                    }
                    .font(.caption2)
                    .foregroundStyle(candidate.isRecoverable ? .green : .orange)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct CleanupResultLabel: View {
    let status: CleanupExecutionStatus
    let title: String
    let message: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.bold())
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: status == .cleaned ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(status == .cleaned ? .green : .orange)
        }
    }
}

private struct ProcessCleanupCandidateRow: View {
    let candidate: ProcessCleanupCandidate
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(candidate.kind.koreanLabel).bold()
                        Text("pid \(candidate.pid)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("메모리 \(DiagnosticEngine.formatBytes(candidate.residentBytes))")
                            .monospacedDigit()
                    }
                    Text(candidate.command)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(candidate.koreanReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text("위험도 \(candidate.risk.koreanLabel)")
                        Text("·")
                        Text("종료 후 복구 불가")
                    }
                    .font(.caption2)
                    .foregroundStyle(.orange)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct CleanupConfirmationView: View {
    @ObservedObject var model: MonitorViewModel
    @Environment(\.dismiss) private var dismiss

    private var irreversibleCount: Int {
        model.selectedCandidates.filter { !$0.isRecoverable }.count
    }

    private var totalSelectionCount: Int {
        model.selectedCandidates.count + model.selectedProcessCandidates.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("정리 전 마지막 확인", systemImage: "checkmark.shield")
                .font(.title2.bold())
            Text("선택한 \(totalSelectionCount)개 항목을 실행 직전에 다시 검사합니다. 조건이 달라진 항목은 건드리지 않습니다.")
            if irreversibleCount > 0 {
                Label("시뮬레이터 \(irreversibleCount)개는 삭제 후 내부 데이터를 복구할 수 없습니다.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            if !model.selectedProcessCandidates.isEmpty {
                Label(
                    "프로세스 \(model.selectedProcessCandidates.count)개 종료는 되돌릴 수 없으며, "
                        + "의도적으로 띄워 둔 서버나 진행 중인 작업을 중단시킬 수 있습니다.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            }
            List {
                ForEach(model.selectedCandidates) { candidate in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(candidate.kind.koreanLabel) — \(candidate.targetIdentifier)")
                            .bold()
                        Text(candidate.recoveryMethod.koreanLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(model.selectedProcessCandidates) { candidate in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(candidate.kind.koreanLabel) — pid \(candidate.pid) 종료(SIGTERM)")
                            .bold()
                        Text("복구 불가 · 위험도 \(candidate.risk.koreanLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(minHeight: 180)
            HStack {
                // 디스크와 메모리는 다른 자원이므로 합산하지 않고 나란히 보여준다.
                VStack(alignment: .leading, spacing: 2) {
                    Text("디스크 예상 최대 확보 \(DiagnosticEngine.formatBytes(model.selectedCleanupBytes))")
                    Text("메모리 예상 회수(상주 메모리 기준) \(DiagnosticEngine.formatBytes(model.selectedProcessMemoryBytes))")
                }
                .font(.callout.monospacedDigit())
                Spacer()
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                // 실수로 Return 키에 반응하지 않도록 defaultAction 단축키를 주지 않는다.
                Button("확인하고 정리") { model.executeSelectedCleanup() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 560, height: 440)
    }
}

private struct ProcessRow: View {
    let process: ClassifiedProcess

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(process.kind.koreanLabel)
                    .font(.callout.bold())
                Text("pid \(process.snapshot.pid)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "CPU %.1f%%  ·  메모리 %@",
                            process.snapshot.cpuPercent,
                            DiagnosticEngine.formatBytes(process.snapshot.residentBytes)))
                    .font(.caption.monospacedDigit())
            }
            Text(process.snapshot.command)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let note = process.uncertaintyNote {
                Label(note, systemImage: "questionmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }
}
