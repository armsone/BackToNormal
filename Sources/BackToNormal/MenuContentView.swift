import SwiftUI
import AppKit
import BackToNormalCore

/// 메뉴 바에서 바로 보이는 요약 화면.
struct MenuContentView: View {
    @ObservedObject var model: MonitorViewModel
    let showDetail: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: model.statusSymbolName)
                    .foregroundStyle(model.statusColor)
                Text("상태: \(model.diagnosis.status.koreanLabel)")
                    .font(.headline)
                Spacer()
            }

            Text(model.diagnosis.keyCause)
                .font(.subheadline)

            if let refreshed = model.lastRefreshed {
                Text("마지막 확인: \(refreshed.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("권장 모드 — 정리는 항상 확인 후 실행합니다")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button {
                    model.refresh()
                } label: {
                    Label("새로고침", systemImage: "arrow.clockwise")
                }
                .disabled(model.isRefreshing)

                Button {
                    showDetail()
                } label: {
                    Label("상세 보기", systemImage: "list.bullet.rectangle")
                }

                Spacer()

                Button("종료") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(12)
        .frame(width: 300)
    }
}
