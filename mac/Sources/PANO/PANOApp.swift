import SwiftUI
import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var store: AppStore?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ n: Notification) {
        UNUserNotificationCenter.current().delegate = self
        // When the main window closes and the app should stay in the menu bar, hide the Dock icon.
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
            guard let w = note.object as? NSWindow, w.identifier?.rawValue.contains("main") == true else { return }
            DispatchQueue.main.async {
                guard let store = self?.store else { return }
                let p = store.prefs
                if p.stayInMenuBar && p.showMenuIcon { NSApp.setActivationPolicy(.accessory) } else { NSApp.terminate(nil) }
            }
        })
    }

    /// Show alerts even while PANO is in front.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Clicking a keyword alert opens the main window on that story; the morning summary opens Bugün,
    /// the evening one Haberler › Günün Özeti.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let newsID = info["newsID"] as? String, screen = info["screen"] as? String, quakeID = info["quakeID"] as? String
        guard newsID != nil || screen != nil else { return }
        await MainActor.run {
            guard let store else { return }
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            if let w = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true }) { w.makeKeyAndOrderFront(nil) }
            else { store.openMainAction?() }
            if let newsID { store.openNews(id: newsID) }
            else if screen == "gunun-ozeti" { store.newsMode = .daily; store.screen = .haberler }
            else if let s = screen.flatMap({ Screen(rawValue: $0 == "bugun" ? "Bugün" : $0) }) {
                if let quakeID { store.quakes.selectedID = quakeID }
                store.screen = s
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct PANOApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store: AppStore

    init() {
        Fonts.register()
        let s = AppStore()
        _store = State(initialValue: s)
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("PANO", id: "main") {
            RootView().environment(store)
                .onAppear { delegate.store = store }
        }
        .defaultSize(width: 1280, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(before: .toolbar) {
                Button(store.prefs.sidebarCollapsed ? "Kenar Çubuğunu Genişlet" : "Kenar Çubuğunu Daralt") {
                    store.prefs.sidebarCollapsed.toggle()
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
                Divider()
            }
        }

        MenuBarExtra(isInserted: Binding(get: { store.prefs.showMenuIcon }, set: { if store.prefs.showMenuIcon != $0 { store.prefs.showMenuIcon = $0 } })) {
            PopoverView().environment(store)
        } label: {
            HStack(spacing: 6) {
                Image(nsImage: MenuBarIcon.image)
                if !store.menuBarText.isEmpty { Text(store.menuBarText).font(.system(size: 11, weight: .medium).monospacedDigit()) }
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environment(store)
        }
        .windowResizability(.contentSize)
    }
}

enum MenuBarIcon {
    /// Bold "P" monogram, single colour (template image), as in the design.
    static let image: NSImage = {
        let font = NSFont.systemFont(ofSize: 15, weight: .bold)
        let str = NSAttributedString(string: "P", attributes: [.font: font, .foregroundColor: NSColor.black, .kern: -0.6])
        let size = NSSize(width: ceil(str.size().width) + 1, height: 16)
        let img = NSImage(size: size, flipped: false) { rect in
            let y = (rect.height - font.capHeight) / 2 + font.descender * 0   // baseline
            str.draw(at: NSPoint(x: 0.5, y: y + font.descender))
            return true
        }
        img.isTemplate = true
        return img
    }()
}
