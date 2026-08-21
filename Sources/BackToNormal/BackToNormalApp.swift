import SwiftUI
import AppKit

@main
struct BackToNormalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(
                model: appDelegate.model,
                showDetail: appDelegate.showDetailWindow
            )
        } label: {
            Image(nsImage: AppArtwork.menuBarIcon)
                .accessibilityLabel("BackToNormal — \(appDelegate.model.diagnosis.status.koreanLabel)")
        }
        .menuBarExtraStyle(.window)
    }
}

private enum AppArtwork {
    static let menuBarIcon: NSImage = {
        let size = NSSize(width: 18, height: 18)
        guard let source = NSApplication.shared.applicationIconImage else {
            return NSImage(size: size)
        }
        return NSImage(size: size, flipped: false) { rect in
            source.draw(
                in: rect,
                from: NSRect(origin: .zero, size: source.size),
                operation: .sourceOver,
                fraction: 1
            )
            return true
        }
    }()
}

/// Dock 아이콘 없이 메뉴 막대에 상주하되, 첫 실행에는 진단 창을 확실히 보여준다.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = MonitorViewModel()
    private var detailWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        showDetailWindow()
    }

    func showDetailWindow() {
        let minimumContentSize = NSSize(width: 680, height: 600)
        let preferredContentSize = fittedDetailContentSize(minimum: minimumContentSize)
        let window: NSWindow
        if let detailWindow {
            window = detailWindow
        } else {
            let controller = NSHostingController(
                rootView: DetailView(model: model)
                    .frame(minWidth: minimumContentSize.width, minHeight: minimumContentSize.height)
            )
            window = NSWindow(
                contentRect: NSRect(origin: .zero, size: preferredContentSize),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "BackToNormal — 상세"
            window.contentViewController = controller
            window.contentMinSize = minimumContentSize
            window.setContentSize(preferredContentSize)
            window.isReleasedWhenClosed = false
            window.center()
            detailWindow = window
        }

        window.contentMinSize = minimumContentSize
        let currentContentSize = window.contentLayoutRect.size
        if currentContentSize.width < minimumContentSize.width
            || currentContentSize.height < minimumContentSize.height {
            window.setContentSize(preferredContentSize)
            window.center()
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func fittedDetailContentSize(minimum: NSSize) -> NSSize {
        let visibleSize = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        return NSSize(
            width: max(minimum.width, min(760, visibleSize.width - 80)),
            height: max(minimum.height, min(760, visibleSize.height - 80))
        )
    }
}
