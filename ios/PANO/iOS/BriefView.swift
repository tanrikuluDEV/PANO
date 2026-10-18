import SwiftUI

/// The evening summary as a page (opened by its notification; the morning one lives in Haberler › Sabah Özeti): what the notification said, with every line leading on — the story,
/// the forecast, the markets, the to-dos, the match. Following any link closes the page and opens that screen.
struct BriefView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let kind: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if kind == "morning" { MorningBriefView() } else { EveningBrief() }
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 32)
            }
            .background(AppBackdrop().ignoresSafeArea())
            .refreshable { await store.refreshSlow(force: true) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Kapat") { dismiss() } }
            }
            .navigationBarTitleDisplayMode(.inline)
            // stories open inside the page; Back returns to the summary
            .navigationDestination(item: Binding(get: { store.phoneStory }, set: { store.phoneStory = $0 })) { NewsDetail(item: $0) }
        }
        // a card's link (story, Hava, Ekonomi, Maçlar …) moves the app; the page gets out of the way
        .onChange(of: store.navRequest) { dismiss() }
        .onDisappear { store.phoneStory = nil }
        .onChange(of: store.webURL) { if store.webURL != nil { dismiss() } }
    }
}

// MARK: - Sabah özeti

/// Sabah özeti: shown in Haberler › Sabah Özeti (what the morning notification lists, each line leading on).
struct MorningBriefView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 20) { content }
    }

    @ViewBuilder private var content: some View {
        let name = store.prefs.userName.trimmingCharacters(in: .whitespaces)
        VStack(alignment: .leading, spacing: 4) {
            Text(name.isEmpty ? "Günaydın ☀️" : "Günaydın \(name) ☀️").font(.serif(28)).tracking(-0.4)
            Text("\(Day.long(Date())) · \(store.prefs.cityName)").font(.ui(13)).foregroundStyle(T.ink2)
        }
        weather
        markets
        headlines
        TodayTodos()
        if !store.prefs.favoriteTeams.isEmpty { TeamCard() }
    }

    @ViewBuilder private var weather: some View {
        if let w = store.weather {
            let today = store.weatherDetail?.daily.first { Day.cal.isDateInToday($0.date) }
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "HAVA", link: "Ayrıntılar →") { store.screen = .hava }
                Button { store.screen = .hava } label: {
                    Card(padding: 16) {
                        HStack(spacing: 14) {
                            Image(systemName: w.summary.symbol).symbolRenderingMode(.multicolor).font(.system(size: 34))
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(w.tempText).font(.mono(30)).tracking(-1)
                                    Text(w.summary.text).font(.serif(17))
                                }
                                if let d = today {
                                    Text("Bugün \(Int(d.tempMin.rounded()))° – \(Int(d.tempMax.rounded()))°"
                                         + (d.precipChance >= 20 ? " · yağış %\(d.precipChance)" : "")
                                         + " · gün doğumu \(Day.hm(d.sunrise))")
                                        .font(.ui(12.5)).foregroundStyle(T.ink2)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var markets: some View {
        let items = ["usd", "eur", "gram"].compactMap { id in allInstruments.first { $0.id == id }.flatMap { i in store.quotes[id].map { (i, $0) } } }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "PİYASALAR", link: "Ekonomi →") { store.screen = .ekonomi }
                HStack(spacing: 8) {
                    ForEach(items, id: \.0.id) { inst, q in
                        Button { store.selectedIndicator = inst.id; store.screen = .ekonomi } label: { EconTile(inst: inst, q: q) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var headlines: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "GÜNÜN MANŞETLERİ", link: "Haberler →") { store.newsMode = .list; store.screen = .haberler }
            Card {
                VStack(spacing: 0) {
                    ForEach(Array(store.topHeadlines.prefix(5).enumerated()), id: \.element.id) { i, n in
                        if i > 0 { Rule(color: T.rule2) }
                        StoryLine(item: n)
                    }
                    if store.topHeadlines.isEmpty {
                        Text("Haberler yükleniyor…").font(.ui(12.5)).foregroundStyle(T.ink3).padding(14)
                    }
                }
            }
        }
    }
}

// MARK: - Günün özeti

private struct EveningBrief: View {
    @Environment(AppStore.self) private var store
    @State private var digest: DailyDigest?

    var body: some View {
        Group { content }
            .task(id: signature) { digest = DailyDigest(news: store.visibleNews, bookmarks: store.bookmarks) }
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Günün Özeti 🌙").font(.serif(28)).tracking(-0.4)
            Text(Day.long(Date()) + (digest.map { " · \($0.total) haber, \($0.sourceCount) kaynak" } ?? ""))
                .font(.ui(13)).foregroundStyle(T.ink2)
        }
        if let d = digest {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                StatTile(label: "BUGÜN", value: "\(d.total)", sub: "haber")
                StatTile(label: "EN ÇOK", value: d.categories.first?.0 ?? "—", sub: d.categories.first.map { "\($0.1) haber" } ?? "")
            }
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "ÖNE ÇIKANLAR")
                if d.topics.isEmpty {
                    EmptyBox(title: "Henüz öne çıkan konu yok", subtitle: "Gün ilerledikçe birden çok kaynağın yazdığı konular burada belirir")
                }
                ForEach(d.topics.prefix(8)) { TopicCard(topic: $0) }
            }
            ShareList(title: "KATEGORİLER", rows: d.categories)
            Button { store.newsMode = .daily; store.screen = .haberler } label: {
                Text("Haberler'de günün tüm özetini aç →").font(.ui(13.5, .medium)).foregroundStyle(T.accent)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(T.accentSoft, in: RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain)
        } else {
            SkeletonCard(title: "HAZIRLANIYOR")
        }
    }

    /// Recompute when the news pool changes or the day rolls over.
    private var signature: String { "\(Day.key())|\(store.visibleNews.count)|\(store.news.first?.id ?? "")" }
}

/// A headline row: source, time and title; opens the story.
private struct StoryLine: View {
    @Environment(AppStore.self) private var store
    let item: NewsItem
    var body: some View {
        Button { store.openNews(item) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(item.source.uppercased()) · \(Day.hm(item.date))").font(.mono(9.5)).tracking(0.5).foregroundStyle(T.accent)
                Text(item.title).font(.serif(15.5)).foregroundStyle(T.ink).multilineTextAlignment(.leading).lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 11).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
