import SwiftUI
import UserNotifications
import AVFoundation

@main
struct PANOApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var phase
    @State private var store: AppStore
    // skipped for simulator screenshots (`-screenshots YES`) unless `-splash YES`
    @State private var splashDone = UserDefaults.standard.bool(forKey: "screenshots") && !UserDefaults.standard.bool(forKey: "splash")

    init() {
        Fonts.register()
        // radio and TV keep playing with the screen locked or another app in front (UIBackgroundModes: audio)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        let s = AppStore()
        // `-startTab Haberler` (from the command line) opens that tab — used for simulator screenshots
        if let t = UserDefaults.standard.string(forKey: "startTab"), let screen = Screen(rawValue: t) { s.screen = screen }
        // `-openFirstNews YES` / `-playFirstStation YES` (with `-radioVolume 0`): screenshot helpers, command line only
        if UserDefaults.standard.bool(forKey: "openFirstNews") {
            Task { @MainActor in
                while s.news.isEmpty { try? await Task.sleep(nanoseconds: 500_000_000) }
                if let n = s.filteredNews.first { s.openNews(n) }
            }
        }
        if UserDefaults.standard.bool(forKey: "playFirstStation") {
            Task { @MainActor in
                while s.radio.stations.isEmpty { try? await Task.sleep(nanoseconds: 500_000_000) }
                s.radio.play(s.radio.stations[0])
            }
        }
        // `-brief morning|evening` (command line only): screenshot of a summary page
        if let b = UserDefaults.standard.string(forKey: "brief") { s.briefToShow = b }
        if let m = UserDefaults.standard.string(forKey: "newsMode"), let mode = NewsMode(rawValue: m) { s.newsMode = mode }
        AppDelegate.store = s
        _store = State(initialValue: s)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                MobileRoot().environment(store)
                if !splashDone { SplashView { splashDone = true }.zIndex(1) }
            }
                .task { await store.scheduleBriefs() }
                // new data, new settings, or leaving the app: rebuild the scheduled summaries and ask for background time
                .onChange(of: store.lastSync) { Task { await store.scheduleBriefs() } }
                .onChange(of: store.prefs) { Task { await store.scheduleBriefs() } }
                .onChange(of: phase) { _, p in
                    if p == .background { BackgroundRefresh.submit(); Task { await store.scheduleBriefs() } }
                }
        }
    }
}
