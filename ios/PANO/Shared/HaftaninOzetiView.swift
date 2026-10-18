import SwiftUI

/// "Haftanın Özeti": a look back over the one-week news window — how much came in each day, which topics
/// the most outlets wrote about, and the category / source mix. Computed on the client from `news`; no fetch.
struct HaftaninOzetiView: View {
    @Environment(AppStore.self) private var store
    @State private var digest: WeeklyDigest?

    var body: some View {
        ScrollView {
            if let d = digest {
                VStack(alignment: .leading, spacing: 22) {
                    stats(d)
                    AdaptiveStack {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "HAFTANIN KONULARI")
                            if d.topics.isEmpty {
                                EmptyBox(title: "Henüz yeterli haber yok", subtitle: "Birkaç yenilemeden sonra konular belirginleşir")
                            }
                            ForEach(d.topics.prefix(6)) { TopicCard(topic: $0) }
                            if d.topics.count > 6 {
                                SectionHeader(title: "DİĞER KONULAR").padding(.top, 6)
                                TopicChips(topics: Array(d.topics.dropFirst(6)))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 22) {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "GÜN GÜN")
                                Card(padding: 16) { DayBars(days: d.perDay) }
                            }
                            ShareList(title: "KATEGORİLER", rows: d.categories)
                            ShareList(title: "EN ÇOK HABER VEREN KAYNAKLAR", rows: Array(d.sources.prefix(8)))
                        }
                        .frame(width: isPhone ? nil : 320)
                    }
                }
                .padding(isPhone ? 16 : 24)
                .frame(maxWidth: 1100, alignment: .leading)
            }
        }
        .task(id: signature) { digest = WeeklyDigest(news: store.visibleNews, bookmarks: store.bookmarks) }
    }

    /// Recompute only when the news pool or the archive actually changes.
    private var signature: String {
        "\(store.visibleNews.count)|\(store.news.first?.id ?? "")|\(store.bookmarks.count)"
    }

    private func stats(_ d: WeeklyDigest) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            StatTile(label: "TOPLAM HABER", value: "\(d.total)", sub: "son 7 gün")
            StatTile(label: "KAYNAK", value: "\(d.sourceCount)", sub: "haber veren")
            StatTile(label: "EN YOĞUN GÜN", value: d.busiest.map { Day.format($0.date, "EEEE") } ?? "—",
                     sub: d.busiest.map { "\($0.count) haber" } ?? "")
            StatTile(label: "ARŞİVE EKLENEN", value: "\(d.archived)", sub: "bu hafta")
        }
    }
}

// MARK: - Digest

struct WeeklyDigest {
    struct Topic: Identifiable {
        let term: String
        let stories: [NewsItem]
        let sourceCount: Int
        var id: String { term }
    }

    let total: Int
    let sourceCount: Int
    let archived: Int
    /// Oldest → newest, always seven entries (days with nothing still show as zero).
    let perDay: [(date: Date, count: Int)]
    let busiest: (date: Date, count: Int)?
    let categories: [(String, Int)]
    let sources: [(String, Int)]
    let topics: [Topic]

    init(news: [NewsItem], bookmarks: [Bookmark]) {
        let cutoff = NewsService.cutoff
        let week = news.filter { $0.date >= cutoff }
        total = week.count
        sourceCount = Set(week.map(\.sourceID)).count
        archived = bookmarks.filter { $0.savedAt >= cutoff }.count

        let byDay = Dictionary(grouping: week) { Day.key(min($0.date, Date())) }.mapValues(\.count)
        perDay = (0..<7).compactMap { i in
            Day.cal.date(byAdding: .day, value: i, to: cutoff).map { d in (d, byDay[Day.key(d)] ?? 0) }
        }
        busiest = perDay.filter { $0.count > 0 }.max { $0.count < $1.count }
        categories = Dictionary(grouping: week, by: \.category).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
        sources = Dictionary(grouping: week, by: \.source).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
        topics = Self.topics(week)
    }

    /// Topics are names and phrases from headlines, ranked by how many different outlets used them — breadth
    /// across sources is what makes a story "the talk of the week", not one busy feed repeating it.
    /// - Two-word phrases ("yapay zeka", "Merkez Bankası") count as one topic.
    /// - A single word only counts if headlines usually capitalise it mid-sentence (people, places, companies),
    ///   which keeps everyday words like "başlıyor" out without an endless stopword list.
    /// - A topic whose stories mostly belong to a higher-ranked one is dropped ("Dursun" under "Dursun Özbek").
    static func topics(_ week: [NewsItem]) -> [Topic] {
        let tr = Locale(identifier: "tr_TR")
        let sourceWords = Set(allNewsSources.flatMap { $0.name.lowercased(with: tr).split(whereSeparator: { !$0.isLetter }).map(String.init) })
        func usable(_ key: String, _ form: String) -> Bool { form.count >= 3 && !stopwords.contains(key) && !sourceWords.contains(key) }

        var stories: [String: [NewsItem]] = [:]
        var forms: [String: [String: Int]] = [:]
        var capitalised: [String: Int] = [:], midSentence: [String: Int] = [:]
        var phrases = Set<String>()
        for n in week {
            // "Erdoğan'dan" → "Erdoğan": drop the suffix after an apostrophe, keep word order for phrases
            let words = n.title.split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "’" })
                .compactMap { $0.split(whereSeparator: { $0 == "'" || $0 == "’" }).first.map(String.init) }
            let sentenceCase = words.filter { $0.count >= 4 && $0.first?.isLowercase == true }.count >= 2
            var seen = Set<String>()
            var prev: (key: String, form: String)?
            func add(_ key: String, _ form: String) {
                guard seen.insert(key).inserted else { return }
                stories[key, default: []].append(n)
                forms[key, default: [:]][form, default: 0] += 1
            }
            for (i, form) in words.enumerated() {
                let key = form.lowercased(with: tr)
                let ok = usable(key, form)
                if ok, form.count >= 4 {
                    add(key, form)
                    if sentenceCase, i > 0 {
                        midSentence[key, default: 0] += 1
                        if form.first?.isUppercase == true { capitalised[key, default: 0] += 1 }
                    }
                }
                if ok, let p = prev {
                    let k = p.key + " " + key
                    phrases.insert(k); add(k, p.form + " " + form)
                }
                prev = ok ? (key, form) : nil
            }
        }

        let candidates = stories.compactMap { key, list -> Topic? in
            let srcs = Set(list.map(\.sourceID)).count
            if phrases.contains(key) {
                guard srcs >= 3, list.count >= 4 else { return nil }
            } else {
                let ctx = midSentence[key] ?? 0
                guard srcs >= 2, list.count >= 3, ctx >= 2, Double(capitalised[key] ?? 0) / Double(ctx) >= 0.6 else { return nil }
            }
            // prefer the way headlines normally write it (not ALL-CAPS "SON DAKİKA" styling)
            let f = forms[key] ?? [:]
            let form = f.filter { $0.key != $0.key.uppercased(with: tr) }.max { $0.value < $1.value }?.key
                ?? key.capitalized(with: tr)
            return Topic(term: form, stories: list.sorted { $0.date > $1.date }, sourceCount: srcs)
        }
        .sorted {
            ($0.sourceCount, $0.stories.count, $0.term.contains(" ") ? 1 : 0) > ($1.sourceCount, $1.stories.count, $1.term.contains(" ") ? 1 : 0)
        }

        var picked: [Topic] = [], covered = Set<String>()
        for t in candidates {
            let overlap = t.stories.filter { covered.contains($0.id) }.count
            if Double(overlap) / Double(t.stories.count) >= 0.7 { continue }
            picked.append(t); covered.formUnion(t.stories.map(\.id))
            if picked.count == 24 { break }
        }
        return picked
    }

    /// Function words, headline filler and calendar words that would otherwise top every week.
    static let stopwords: Set<String> = [
        "için", "ile", "gibi", "daha", "olan", "oldu", "olarak", "olduğu", "sonra", "önce", "yeni", "göre", "kadar",
        "değil", "ancak", "bile", "şimdi", "nasıl", "neden", "hangi", "zaman", "bugün", "yarın", "haber", "haberi",
        "haberleri", "işte", "canlı", "video", "izle", "galeri", "fotoğraf", "belli", "geldi", "etti", "yaptı",
        "yapılan", "edildi", "verdi", "dedi", "saat", "milyon", "milyar", "büyük", "önemli", "flaş", "dakika",
        "açıklama", "açıklandı", "açıkladı", "açıklaması", "sonrası", "yeniden", "ilgili", "karşı", "arasında",
        "üzerine", "tarafından", "diye", "başladı", "devam", "ediyor", "geliyor", "oluyor", "olacak", "olmak",
        "birlikte", "yüzde", "iddia", "tepki", "sonunda", "aldı", "attı", "çıktı", "kaldı", "gelen", "giden",
        "şöyle", "böyle", "bunu", "buna", "bunun", "onun", "şunu", "kendi", "herkes", "hiçbir", "bütün", "tüm",
        "türkiye", "türkiye'de", "dünya", "ocak", "şubat", "mart", "nisan", "mayıs", "haziran", "temmuz", "ağustos",
        "eylül", "ekim", "kasım", "aralık", "pazartesi", "salı", "çarşamba", "perşembe", "cuma", "cumartesi", "pazar",
        "yılı", "yılın", "günü", "gün", "hafta", "haftası", "ayında", "nedir", "neler", "kimdir", "nerede", "mı", "mi",
        "sözleri", "sözü", "açıktı", "resmi", "resmen", "ilk", "son", "iki", "üç", "dört", "beş", "yüz", "bin",
        "başkanı", "başlıyor", "ortaya", "geri", "özel", "mesajı", "kararı", "hakkında", "yükseldi", "tarihi",
        "gelişme", "yıllık", "dolarlık", "genel", "takımı", "deki", "daki", "dan", "den", "nin", "nın",
    ]
}

// MARK: - Pieces

struct StatTile: View {
    let label: String, value: String, sub: String
    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(label).font(.mono(9)).tracking(0.8).foregroundStyle(T.ink3)
                Text(value).font(.serif(24)).tracking(-0.3).lineLimit(1).minimumScaleFactor(0.6)
                Text(sub).font(.mono(10, .regular)).foregroundStyle(T.ink3)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One of the week's top topics: the word, how widely it was covered, and its three newest headlines.
struct TopicCard: View {
    @Environment(AppStore.self) private var store
    let topic: WeeklyDigest.Topic
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                Button { search(topic.term, store) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(topic.term).font(.serif(19)).tracking(-0.2).foregroundStyle(T.ink)
                        Text("\(topic.stories.count) haber · \(topic.sourceCount) kaynak").font(.mono(10, .regular)).foregroundStyle(T.ink3)
                        Spacer()
                        Text("Tümü →").font(.ui(11.5)).foregroundStyle(T.accent)
                    }
                    .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8).contentShape(Rectangle())
                }.buttonStyle(.plain)
                ForEach(topic.stories.prefix(3)) { n in
                    Rule(color: T.rule2)
                    Button { store.openNews(n) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(n.source.uppercased()).font(.mono(9)).tracking(0.5).foregroundStyle(T.accent)
                                .frame(width: 92, alignment: .leading).lineLimit(1)
                            Text(n.title).font(.ui(12.5)).foregroundStyle(T.ink2).lineLimit(1)
                            Spacer(minLength: 6)
                            Text(Day.relativeName(n.date).capitalized(with: Locale(identifier: "tr_TR")))
                                .font(.mono(9.5, .regular)).foregroundStyle(T.ink3).fixedSize()
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

private struct TopicChips: View {
    @Environment(AppStore.self) private var store
    let topics: [WeeklyDigest.Topic]
    var body: some View {
        FlowChips(items: topics) { t in
            Button { search(t.term, store) } label: {
                HStack(spacing: 6) {
                    Text(t.term).font(.ui(12)).foregroundStyle(T.ink).lineLimit(1)
                    Text("\(t.stories.count)").font(.mono(10, .regular)).foregroundStyle(T.ink3)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(T.paper2, in: Capsule()).overlay(Capsule().stroke(T.rule, lineWidth: 1))
                .contentShape(Capsule())
            }.buttonStyle(.plain)
        }
    }
}

/// Seven columns, one per day; today in the accent colour, counts on top.
private struct DayBars: View {
    let days: [(date: Date, count: Int)]
    var body: some View {
        let maxCount = max(days.map(\.count).max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(days, id: \.date) { d in
                let today = Day.daysAgo(d.date) == 0
                VStack(spacing: 5) {
                    Text("\(d.count)").font(.mono(9.5, .regular)).foregroundStyle(T.ink3)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(today ? T.accent : T.ink3.opacity(0.45))
                        .frame(height: max(3, 96 * CGFloat(d.count) / CGFloat(maxCount)))
                    Text(Day.format(d.date, "EEE")).font(.mono(9.5, today ? .semibold : .regular))
                        .foregroundStyle(today ? T.accent : T.ink2)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 140, alignment: .bottom)
    }
}

/// Label, count and a proportional bar per row.
struct ShareList: View {
    let title: String
    let rows: [(String, Int)]
    var body: some View {
        let maxCount = max(rows.map(\.1).max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title)
            Card(padding: 14) {
                VStack(spacing: 9) {
                    ForEach(rows, id: \.0) { name, count in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(name).font(.ui(12)).foregroundStyle(T.ink).lineLimit(1)
                                Spacer()
                                Text("\(count)").font(.mono(10.5, .regular)).foregroundStyle(T.ink3)
                            }
                            GeometryReader { g in
                                Capsule().fill(T.accent.opacity(0.75))
                                    .frame(width: max(3, g.size.width * CGFloat(count) / CGFloat(maxCount)))
                            }
                            .frame(height: 4)
                            .background(T.paper3, in: Capsule())
                        }
                    }
                }
            }
        }
    }
}

/// Jump from a topic to the Haberler list, searching for it across every category.
@MainActor private func search(_ term: String, _ store: AppStore) {
    store.newsSourceFilter = nil
    store.newsQuery = term
    store.newsMode = .list
    store.screen = .haberler   // from a summary page outside Haberler too
}
