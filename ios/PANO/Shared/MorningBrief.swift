import Foundation
import UserNotifications

/// Sabah özeti: one notification each morning at the chosen hour with the weather, markets, top headlines,
/// today's open to-dos and the followed team's match. If the Mac was asleep or PANO wasn't running at that time,
/// it goes out when PANO is next running, as long as that's within four hours; otherwise it waits for tomorrow.
extension AppStore {
    private static let lastKey = "morningBriefLastDay"
    private static var sending = false

    /// Called from the 1-second tick.
    func checkMorningBrief(_ now: Date) {
        guard prefs.morningBrief, !Self.sending else { return }
        let today = Day.key(now)
        guard UserDefaults.standard.string(forKey: Self.lastKey) != today,
              let due = Day.cal.date(bySettingHour: prefs.morningHour, minute: 0, second: 0, of: now),
              now >= due, now < due.addingTimeInterval(4 * 3600) else { return }
        UserDefaults.standard.set(today, forKey: Self.lastKey)
        Task { try? await sendMorningBrief() }
    }

    /// Refreshes what's stale, then posts the summary. Also used by Ayarlar' "Şimdi dene".
    func sendMorningBrief() async throws {
        Self.sending = true
        defer { Self.sending = false }
        if lastSync.map({ Date().timeIntervalSince($0) > 15 * 60 }) ?? true { await refreshSlow(force: true) }
        if let team = prefs.favoriteTeams.first { await refreshTeam(team) }
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "morning-\(Day.key())", content: morningContent(), trigger: nil))
    }

    /// The summary from what's loaded now (the phone also schedules it ahead of time with this).
    func morningContent() -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        let name = prefs.userName.trimmingCharacters(in: .whitespaces)
        c.title = name.isEmpty ? "Günaydın ☀️" : "Günaydın \(name) ☀️"
        c.subtitle = "\(Day.long(Date())) · \(prefs.cityName)"
        c.body = morningLines().joined(separator: "\n")
        c.sound = .default
        c.userInfo = ["screen": "bugun"]
        c.threadIdentifier = "morning"
        c.badge = 1
        return c
    }

    private func morningLines() -> [String] {
        var lines: [String] = []

        if let w = weather {
            var s = "\(w.summary.text), \(w.tempText)"
            if let d = weatherDetail?.daily.first(where: { Day.cal.isDateInToday($0.date) }) {
                s += " · bugün \(Int(d.tempMin.rounded()))°–\(Int(d.tempMax.rounded()))°"
                if d.precipChance >= 30 { s += ", yağış %\(d.precipChance)" }
            }
            lines.append("🌤 " + s)
        }

        let fx = ["usd", "gram"].compactMap { id -> String? in
            guard let inst = allInstruments.first(where: { $0.id == id }), let q = quotes[id] else { return nil }
            return "\(id == "usd" ? "Dolar" : "Gram altın") \(inst.priceText(q)) (\(q.changeText))"
        }
        if !fx.isEmpty { lines.append("💵 " + fx.joined(separator: " · ")) }

        for h in topHeadlines.prefix(3) { lines.append("📰 \(h.title)") }

        let open = todos(on: Day.key()).filter { !$0.done }
        if !open.isEmpty {
            let names = open.prefix(3).map(\.title).joined(separator: ", ")
            lines.append("✓ \(open.count) görev: \(names)\(open.count > 3 ? "…" : "")")
        }

        if let team = prefs.favoriteTeams.first, let info = teamInfo[team] {
            if let n = info.next, let days = Day.cal.dateComponents([.day], from: Day.cal.startOfDay(for: Date()), to: Day.cal.startOfDay(for: n.date)).day, days <= 1 {
                lines.append("⚽ \(days == 0 ? "Bugün" : "Yarın") \(Day.hm(n.date)) · \(n.home ? "\(team) – \(n.opponent)" : "\(n.opponent) – \(team)")")
            } else if let r = info.recent.first, Day.cal.isDateInYesterday(r.date), let gf = r.goalsFor, let ga = r.goalsAgainst {
                lines.append("⚽ Dün: \(team) \(gf)–\(ga) \(r.opponent)")
            }
        }
        return lines.isEmpty ? ["Güzel bir gün geçir."] : lines
    }
}
