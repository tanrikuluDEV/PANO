import SwiftUI
import UserNotifications
import BackgroundTasks

/// iPhone notifications. The Mac sends the morning / evening summaries from a once-a-second check while it runs;
/// iOS suspends the app in the background, so here they are handed to the system ahead of time with a calendar
/// trigger and fire with the app closed. Their text is rebuilt whenever fresh data comes in (app open, background
/// refresh); if the next one is for a later day than the data, a short "tap to see" text goes instead of stale news.
extension AppStore {
    static let morningID = "morning-next", eveningID = "evening-next"

    func scheduleBriefs() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.morningID, Self.eveningID])
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }
        if prefs.morningBrief {
            await schedule(Self.morningID, hour: prefs.morningHour, minute: 0, fresh: morningContent()) {
                $0.title = "Günaydın ☀️"; $0.body = "Hava, piyasalar, manşetler ve görevlerin için dokun."
            }
        }
        if prefs.eveningBrief {
            await schedule(Self.eveningID, hour: prefs.eveningMinute / 60, minute: prefs.eveningMinute % 60, fresh: eveningContent()) {
                $0.title = "Günün Özeti 🌙"; $0.body = "Günün öne çıkan haberleri için dokun."
            }
        }
    }

    private func schedule(_ id: String, hour: Int, minute: Int, fresh: UNMutableNotificationContent,
                          stale: (UNMutableNotificationContent) -> Void) async {
        let now = Date()
        guard var fire = Day.cal.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return }
        if fire <= now { fire = Day.cal.date(byAdding: .day, value: 1, to: fire) ?? fire }
        var content = fresh
        if !Day.cal.isDate(fire, inSameDayAs: now) {
            // today's news would be yesterday's by then
            let c = UNMutableNotificationContent()
            stale(c)
            c.sound = .default; c.userInfo = fresh.userInfo; c.threadIdentifier = fresh.threadIdentifier; c.badge = 1
            content = c
        }
        let when = Day.cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}

/// Background refresh: iOS wakes the app now and then (its own schedule, usually every 15 min to a few hours) to
/// fetch news, markets, weather, fuel prices and earthquakes — which also sends keyword, fuel and earthquake alerts —
/// and to rebuild the scheduled summaries.
enum BackgroundRefresh {
    static let id = "com.ruzname.pano.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            submit()
            let work = Task { @MainActor in
                if let store = AppDelegate.store {
                    await store.refreshSlow(force: true)
                    await store.refreshQuakes()
                    await store.scheduleBriefs()
                }
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    static func submit() {
        let r = BGAppRefreshTaskRequest(identifier: id)
        r.earliestBeginDate = Date().addingTimeInterval(20 * 60)
        try? BGTaskScheduler.shared.submit(r)
    }
}

/// Shows alerts while PANO is in front, and opens the right screen when one is tapped: a story, Deprem, or — for
/// the morning summary — Haberler › Sabah Özeti, or the evening summary's page.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    @MainActor static var store: AppStore?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BackgroundRefresh.register()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let newsID = info["newsID"] as? String, screen = info["screen"] as? String, quakeID = info["quakeID"] as? String
        let thread = response.notification.request.content.threadIdentifier
        await MainActor.run {
            guard let store = Self.store else { return }
            if let newsID {
                store.openNews(id: newsID)
            } else if thread == "morning" {
                // what the notification listed, each line leading on
                store.newsMode = .morning
                store.screen = .haberler
            } else if thread == "evening" || screen == "gunun-ozeti" {
                store.briefToShow = "evening"
            } else if let s = screen.flatMap({ Screen(rawValue: $0 == "bugun" ? "Bugün" : $0) }) {
                if let quakeID { store.quakes.selectedID = quakeID }
                store.screen = s
            }
        }
    }
}
