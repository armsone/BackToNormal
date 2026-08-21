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
            Image(systemName: appDelegate.model.statusSymbolName)
        }
        .menuBarExtraStyle(.window)
    }
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
        let window: NSWindow
        if let detailWindow {
            window = detailWindow
        } else {
            let controller = NSHostingController(rootView: DetailView(model: model))
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 820),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "BackToNormal — 상세"
            window.contentViewController = controller
            window.minSize = NSSize(width: 620, height: 640)
            window.isReleasedWhenClosed = false
            window.center()
            detailWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
