import SwiftUI
import UserNotifications

/// "Günün Özeti": today's news only — the topics the most outlets wrote about, the category mix and the
/// latest headlines. Shown as a mode of Haberler, and opened by the evening notification.
struct GununOzetiView: View {
    @Environment(AppStore.self) private var store
    @State private var digest: DailyDigest?

    var body: some View {
        ScrollView {
            if let d = digest {
                VStack(alignment: .leading, spacing: 22) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        StatTile(label: "BUGÜN", value: "\(d.total)", sub: "haber")
                        StatTile(label: "KAYNAK", value: "\(d.sourceCount)", sub: "haber veren")
                        StatTile(label: "EN ÇOK", value: d.categories.first?.0 ?? "—", sub: d.categories.first.map { "\($0.1) haber" } ?? "")
                        StatTile(label: "ARŞİVE EKLENEN", value: "\(d.archived)", sub: "bugün")
                    }
                    AdaptiveStack {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "GÜNÜN ÖNE ÇIKANLARI")
                            if d.topics.isEmpty {
                                EmptyBox(title: "Henüz öne çıkan konu yok", subtitle: "Gün ilerledikçe birden çok kaynağın yazdığı konular burada belirir")
                            }
                            ForEach(d.topics.prefix(8)) { TopicCard(topic: $0) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 22) {
                            ShareList(title: "KATEGORİLER", rows: d.categories)
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "SON MANŞETLER")
                                Card {
                                    VStack(alignment: .leading, spacing: 0) {
                                        ForEach(Array(store.topHeadlines.enumerated()), id: \.element.id) { i, n in
                                            if i > 0 { Rule(color: T.rule2) }
                                            Button { store.openNews(n) } label: {
                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text("\(n.source.uppercased()) · \(Day.hm(n.date))").font(.mono(9)).tracking(0.5).foregroundStyle(T.accent)
                                                    Text(n.title).font(.ui(12.5)).foregroundStyle(T.ink2).lineLimit(2)
                                                        .multilineTextAlignment(.leading)
                                                }
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.horizontal, 14).padding(.vertical, 9).contentShape(Rectangle())
                                            }.buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(width: isPhone ? nil : 320)
                    }
                }
                .padding(isPhone ? 16 : 24)
                .frame(maxWidth: 1100, alignment: .leading)
            }
        }
        .task(id: signature) { digest = DailyDigest(news: store.visibleNews, bookmarks: store.bookmarks) }
        .onAppear { AppStore.clearBadge() }
    }

    /// Recompute only when the news pool or the archive changes (or the day rolls over).
    private var signature: String {
        "\(Day.key())|\(store.visibleNews.count)|\(store.news.first?.id ?? "")|\(store.bookmarks.count)"
    }
}

struct DailyDigest {
    let total: Int
    let sourceCount: Int
    let archived: Int
    let categories: [(String, Int)]
    let topics: [WeeklyDigest.Topic]

    init(news: [NewsItem], bookmarks: [Bookmark], day: Date = Date()) {
        let today = news.filter { Day.cal.isDate(min($0.date, Date()), inSameDayAs: day) }
        total = today.count
        sourceCount = Set(today.map(\.sourceID)).count
        archived = bookmarks.filter { Day.cal.isDate($0.savedAt, inSameDayAs: day) }.count
        categories = Dictionary(grouping: today, by: \.category).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
        topics = WeeklyDigest.topics(today)
    }
}

/// Günün özeti notification: sent once a day at the chosen time with the day's top topics. If the Mac was
/// asleep or PANO wasn't running then, it goes out when PANO is next running, as long as it's still the same day.
extension AppStore {
    /// The summaries put a 1 on the Dock icon; seeing Bugün or Günün Özeti clears it.
    static func clearBadge() {
        // only once notifications are allowed: on iOS touching the badge before that brings up the permission prompt
        let c = UNUserNotificationCenter.current()
        c.getNotificationSettings { s in if s.authorizationStatus == .authorized { c.setBadgeCount(0) } }
    }

    private static let eveningLastKey = "eveningBriefLastDay"
    private static var eveningSending = false

    /// Called from the 1-second tick.
    func checkEveningBrief(_ now: Date) {
        guard prefs.eveningBrief, !Self.eveningSending else { return }
        let today = Day.key(now)
        guard UserDefaults.standard.string(forKey: Self.eveningLastKey) != today,
              let due = Day.cal.date(bySettingHour: prefs.eveningMinute / 60, minute: prefs.eveningMinute % 60, second: 0, of: now),
              now >= due else { return }
        UserDefaults.standard.set(today, forKey: Self.eveningLastKey)
        Task { try? await sendEveningBrief() }
    }

    /// Refreshes the news if stale, then posts the summary. Also used by Ayarlar' "Şimdi dene".
    func sendEveningBrief() async throws {
        Self.eveningSending = true
        defer { Self.eveningSending = false }
        if lastSync.map({ Date().timeIntervalSince($0) > 15 * 60 }) ?? true { await refreshSlow(force: true) }
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "evening-\(Day.key())", content: eveningContent(), trigger: nil))
    }

    /// The summary from what's loaded now (the phone also schedules it ahead of time with this).
    func eveningContent() -> UNMutableNotificationContent {
        let d = DailyDigest(news: visibleNews, bookmarks: bookmarks)
        let c = UNMutableNotificationContent()
        c.title = "Günün Özeti 🌙"
        c.subtitle = "\(Day.long(Date())) · \(d.total) haber, \(d.sourceCount) kaynak"
        var lines = d.topics.prefix(4).compactMap { t in t.stories.first.map { "• \(t.term): \($0.title)" } }
        if lines.isEmpty { lines = topHeadlines.prefix(4).map { "📰 \($0.title)" } }
        c.body = lines.isEmpty ? "Bugün için henüz haber yok." : lines.joined(separator: "\n")
        c.sound = .default
        c.userInfo = ["screen": "gunun-ozeti"]
        c.threadIdentifier = "evening"
        c.badge = 1
        return c
    }
}
