import SwiftUI

struct HaberlerView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Text("Haberler").font(.serif(25)).tracking(-0.4)
                    ModeSwitch(selection: $store.newsMode, options: [(.list, "Liste"), (.daily, "Günün Özeti"), (.weekly, "Haftanın Özeti")])
                    Spacer()
                    if store.newsMode == .list {
                    Text(store.newsQuery.trimmingCharacters(in: .whitespaces).isEmpty ? "\(store.filteredNews.count) başlık · \(store.activeSources.count) kaynak" : "\(store.filteredNews.count) sonuç").font(.mono(11, .regular)).foregroundStyle(T.ink3)
                    }
                }
                if store.newsMode == .list {
                HStack(spacing: 8) {
                    ForEach(newsCategories, id: \.self) { k in
                        Button { store.newsQuery = ""; store.newsCategory = k } label: { Pill(text: k, selected: store.newsCategory == k) }.buttonStyle(.plain)
                    }
                    .opacity(store.newsQuery.trimmingCharacters(in: .whitespaces).isEmpty ? 1 : 0.4)
                    VRule().frame(height: 20).padding(.horizontal, 4)
                    Menu {
                        Button("Tümü") { store.newsSourceFilter = nil }
                        Divider()
                        ForEach(store.activeSources) { s in Button(s.name) { store.newsSourceFilter = s.id } }
                    } label: {
                        Text("Kaynak: \(allNewsSources.first { $0.id == store.newsSourceFilter }?.name ?? "Tümü") ▾")
                            .font(.ui(12)).foregroundStyle(T.ink2)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(T.paper2, in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(T.rule, lineWidth: 1))
                    }.menuStyle(.button).buttonStyle(.plain).fixedSize()
                    Spacer(minLength: 8)
                    HStack(spacing: 6) {
                        Text("⌕").font(.ui(13)).foregroundStyle(T.ink3)
                        TextField("Haberlerde ara", text: $store.newsQuery).textFieldStyle(.plain).font(.ui(12.5)).frame(width: 170)
                        if !store.newsQuery.isEmpty {
                            Button { store.newsQuery = "" } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(T.ink3)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(T.paper2, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(T.rule, lineWidth: 1))
                }
                }
                if !store.failedSources.isEmpty {
                    Text("Alınamayan kaynaklar: \(store.failedSources.sorted().joined(separator: ", "))")
                        .font(.mono(10, .regular)).foregroundStyle(T.ink3)
                }
            }
            .padding(.screenHeader)
            .overlay(alignment: .bottom) { Rule() }

            content
        }
    }

    @ViewBuilder private var content: some View {
        if store.newsMode == .daily, !store.news.isEmpty {
            GununOzetiView()
        } else if store.newsMode == .weekly, !store.news.isEmpty {
            HaftaninOzetiView()
        } else if case .failed(let m) = store.newsState, store.news.isEmpty {
            ErrorCard(eyebrow: "HATA · HABERLER", message: m) { Task { await store.refreshNews() } }
                .frame(maxWidth: 340).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if store.news.isEmpty {
            SkeletonCard(title: "YÜKLENİYOR · HABERLER", widths: [0.8, 0.95, 0.6, 0.9, 0.7])
                .frame(maxWidth: 340).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if store.filteredNews.isEmpty {
            let searching = !store.newsQuery.trimmingCharacters(in: .whitespaces).isEmpty
            EmptyBox(title: searching ? "“\(store.newsQuery)” için sonuç yok" : "Bu kategoride haber yok",
                     subtitle: searching ? "Başka bir kelime dene" : "Başka bir kategori ya da kaynak dene").padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            HStack(spacing: 0) {
                // the "Kaldığın yer" line only makes sense in the plain feed, not in search results
                let mark = store.newsQuery.trimmingCharacters(in: .whitespaces).isEmpty ? store.newsReadMark : nil
                NewsDayList(items: store.filteredNews, selectedID: store.selectedNews?.id, readMark: mark) { store.selectedNewsID = $0.id }
                .frame(width: 432)
                .overlay(alignment: .trailing) { VRule() }
                if let n = store.selectedNews { NewsDetail(item: n) }
            }
        }
    }
}

/// News list split into days, newest first, each under a pinned separator: BUGÜN, DÜN, then weekday names.
struct NewsDayList: View {
    @Environment(AppStore.self) private var store
    let items: [NewsItem]
    let selectedID: String?
    /// Stories newer than this are "new since last visit": a banner counts them and a line marks where they end.
    var readMark: Date? = nil
    /// Fold the same story from several outlets into one row (when switched on in Ayarlar).
    var fold = true
    var onSelect: (NewsItem) -> Void
    /// Rows whose other sources are shown.
    @State private var expanded: Set<String> = []

    /// One row: the newest story of a group, plus the other outlets' versions of it (in this list).
    private struct Entry: Identifiable { let item: NewsItem; var others: [NewsItem]; var id: String { item.id } }

    /// `items` is newest-first, so a group's first appearance is its newest story.
    private var entries: [Entry] {
        guard fold, store.prefs.foldDuplicates else { return items.map { Entry(item: $0, others: []) } }
        var out: [Entry] = [], at: [String: Int] = [:]
        for n in items {
            guard let c = store.storyCluster[n.id] else { out.append(Entry(item: n, others: [])); continue }
            if let i = at[c] { out[i].others.append(n) } else { at[c] = out.count; out.append(Entry(item: n, others: [])) }
        }
        return out
    }

    /// Consecutive runs of the same day are the groups.
    private func days(_ entries: [Entry]) -> [(key: String, date: Date, items: [Entry])] {
        var out: [(key: String, date: Date, items: [Entry])] = []
        for e in entries {
            let d = min(e.item.date, Date())   // a feed's clock running ahead still lands under BUGÜN
            let k = Day.key(d)
            if out.last?.key == k { out[out.count - 1].items.append(e) } else { out.append((k, d, [e])) }
        }
        return out
    }

    var body: some View {
        let entries = entries
        let newCount = readMark.map { m in entries.prefix { $0.item.date > m }.count } ?? 0
        // the first already-seen story, only when something new sits above it
        let resumeID = newCount > 0 && newCount < entries.count ? entries[newCount].id : nil
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    if let resumeID {
                        Button { withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo("resume", anchor: .top) } } label: {
                            HStack(spacing: 8) {
                                Circle().fill(T.accent).frame(width: 6, height: 6)
                                Text("Son okumandan beri \(newCount) yeni haber").font(.ui(12, .medium)).foregroundStyle(T.ink)
                                Spacer()
                                Text("Kaldığın yere git ↓").font(.ui(12)).foregroundStyle(T.accent)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(T.accentSoft).contentShape(Rectangle())
                        }.buttonStyle(.plain).id("banner-\(resumeID)")
                    }
                    ForEach(days(entries), id: \.key) { g in
                        Section {
                            ForEach(g.items) { e in
                                let h = e.item
                                if h.id == resumeID { ResumeMarker().id("resume") }
                                let open = expanded.contains(h.id) || e.others.contains { $0.id == selectedID }
                                NewsRow(item: h, selected: h.id == selectedID, unread: readMark.map { h.date > $0 } ?? false,
                                        otherSources: e.others.count, expanded: open,
                                        onToggle: { withAnimation(.easeOut(duration: 0.18)) { if open { expanded.remove(h.id) } else { expanded.insert(h.id) } } }) { onSelect(h) }
                                if open {
                                    ForEach(e.others) { o in OtherSourceRow(item: o, selected: o.id == selectedID) { onSelect(o) } }
                                }
                            }
                        } header: {
                            NewsDayHeader(date: g.date, count: g.items.count)
                        }
                    }
                }
            }
        }
    }
}

/// "Kaldığın yer" — the line between stories that arrived since the last visit and those already seen.
struct ResumeMarker: View {
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(T.accent).frame(height: 1.5)
            Text("KALDIĞIN YER").font(.mono(9.5, .semibold)).tracking(1.2).foregroundStyle(T.accent).fixedSize()
            Rectangle().fill(T.accent).frame(height: 1.5)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}

/// Small two-or-more-way switch in the screen header (Liste / Haftanın Özeti).
struct ModeSwitch<V: Hashable>: View {
    @Binding var selection: V
    let options: [(V, String)]
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { v, label in
                let sel = selection == v
                Button { withAnimation(.easeOut(duration: 0.15)) { selection = v } } label: {
                    Text(label).font(.ui(12, sel ? .semibold : .regular)).foregroundStyle(sel ? T.ink : T.ink2)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(sel ? T.paper2 : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(sel ? T.rule : .clear, lineWidth: 1))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(T.paper3, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct NewsDayHeader: View {
    let date: Date
    let count: Int
    var body: some View {
        let ago = Day.daysAgo(date)
        HStack(spacing: 10) {
            Text(Day.relativeName(date)).font(.mono(10.5, .semibold)).tracking(1.2)
                .foregroundStyle(ago == 0 ? T.accent : T.ink)
            Rectangle().fill(T.rule).frame(height: 1)
            Text("\(Day.format(date, ago < 2 ? "d MMMM EEEE" : "d MMMM")) · \(count) haber")
                .font(.mono(9.5, .regular)).foregroundStyle(T.ink3).fixedSize()
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 9)
        .barBackground()
        .overlay(alignment: .bottom) { Rule(color: T.rule2) }
    }
}

struct NewsRow: View {
    @Environment(AppStore.self) private var store
    let item: NewsItem
    let selected: Bool
    var unread = false
    /// How many other outlets carry the same story (folded under this row).
    var otherSources = 0
    var expanded = false
    var onToggle: () -> Void = {}
    var onSelect: () -> Void
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    if unread { Circle().fill(T.accent).frame(width: 5, height: 5).help("Yeni") }
                    Text(item.source.uppercased()).font(.mono(9.5)).tracking(0.6).foregroundStyle(T.accent)
                    Text(Day.hm(item.date)).font(.mono(10, .regular)).foregroundStyle(T.ink3)
                    if let k = store.matchedKeyword(item) {
                        Image(systemName: "bell.fill").font(.system(size: 8.5)).foregroundStyle(T.accent).help("Takip edilen kelime: \(k)")
                    }
                    if store.isBookmarked(item.id) {
                        Image(systemName: "bookmark.fill").font(.system(size: 9)).foregroundStyle(T.accent).help("Arşivde")
                    }
                    Spacer()
                    if otherSources > 0 {
                        Button(action: onToggle) {
                            HStack(spacing: 3) {
                                Text("+\(otherSources) kaynak")
                                Image(systemName: "chevron.down").font(.system(size: 7.5, weight: .bold)).rotationEffect(.degrees(expanded ? 180 : 0))
                            }
                            .font(.mono(9, .medium)).foregroundStyle(T.accent)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(T.accentSoft, in: RoundedRectangle(cornerRadius: 4))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain).help("Aynı haberi veren diğer kaynaklar")
                    }
                    Text(item.category).font(.mono(9, .regular)).foregroundStyle(T.ink2)
                        .padding(.horizontal, 6).padding(.vertical, 3).background(T.paper3, in: RoundedRectangle(cornerRadius: 4))
                }
                Text(item.title).font(.serif(15)).lineSpacing(3).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background(selected ? T.accentSoft : .clear)
            .overlay(alignment: .leading) { Rectangle().fill(selected ? T.accent : .clear).frame(width: 2) }
            .overlay(alignment: .bottom) { Rule(color: T.rule2) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(store.isBookmarked(item.id) ? "Arşivden çıkar" : "Arşive ekle") { store.toggleBookmark(item) }
            if let l = item.link {
                Button("Kaynakta aç") { store.openWeb(l) }
                Button("Tarayıcıda aç") { NSWorkspace.shared.open(l) }
            }
        }
    }
}

/// Another outlet's version of a folded story, shown indented under the group's row.
struct OtherSourceRow: View {
    let item: NewsItem
    let selected: Bool
    var onSelect: () -> Void
    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.source.uppercased()).font(.mono(9)).tracking(0.5).foregroundStyle(T.accent)
                    .frame(width: 96, alignment: .leading).lineLimit(1)
                Text(item.title).font(.ui(12.5)).foregroundStyle(T.ink2).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 6)
                Text(Day.hm(item.date)).font(.mono(9.5, .regular)).foregroundStyle(T.ink3)
            }
            .padding(.leading, 28).padding(.trailing, 16).padding(.vertical, 8)
            .background(selected ? T.accentSoft : T.paper2.opacity(0.5))
            .overlay(alignment: .leading) { Rectangle().fill(selected ? T.accent : T.rule).frame(width: 2).padding(.leading, 16) }
            .overlay(alignment: .bottom) { Rule(color: T.rule2) }
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

struct NewsDetail: View {
    @Environment(AppStore.self) private var store
    let item: NewsItem
    @State private var saved = false

    private var state: ArticleState { store.articles[item.id] ?? .loading }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Text(item.source.uppercased()).font(.mono(10)).tracking(0.8).foregroundStyle(T.accent)
                    Circle().fill(T.ink3).frame(width: 3, height: 3)
                    Text("\(Day.format(item.date, "d MMMM")) · \(Day.hm(item.date))").font(.mono(10.5, .regular)).foregroundStyle(T.ink3)
                }
                Text(item.title).font(.serif(isPhone ? 25 : 31)).tracking(-0.55).lineSpacing(3).textSelection(.enabled)
                NewsImage(url: item.imageURL ?? store.articleImages[item.id], label: "haber görseli · 16:9", labelSize: 10, spacing: 9)
                    .frame(maxWidth: .infinity).frame(height: 196).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(T.rule2, lineWidth: 1))
                articleBody
                actions
            }
            .padding(.horizontal, isPhone ? 18 : 34).padding(.vertical, isPhone ? 18 : 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(T.paper2)
        .id(item.id)
        .task(id: item.id) { await store.loadArticle(item) }
        .onChange(of: item.id) { saved = false }
    }

    @ViewBuilder private var articleBody: some View {
        switch state {
        case .loading:
            VStack(alignment: .leading, spacing: 14) {
                if !item.summary.isEmpty { paragraph(item.summary) }
                SkeletonCard(title: "MAKALE YÜKLENİYOR", widths: [0.95, 0.88, 0.97, 0.7, 0.92, 0.6]).frame(maxWidth: 560)
            }
        case .loaded(let blocks):
            blocksView(blocks)
        case .partial(let blocks):
            VStack(alignment: .leading, spacing: 14) {
                blocksView(blocks)
                HStack(spacing: 8) {
                    Circle().fill(T.ink3).frame(width: 6, height: 6)
                    Text("Kaynak metnin tamamını sunmuyor; yalnızca özet gösteriliyor.").font(.ui(12)).foregroundStyle(T.ink3)
                }
                .padding(10).frame(maxWidth: 560, alignment: .leading)
                .background(T.paper3, in: RoundedRectangle(cornerRadius: 9))
            }
        case .failed(let msg):
            ErrorCard(title: "Metin alınamadı", message: msg, actionTitle: "Tekrar dene") {
                store.articles[item.id] = nil
                Task { await store.loadArticle(item) }
            }.frame(maxWidth: 340)
        }
    }

    private func blocksView(_ blocks: [ArticleBlock]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(blocks) { b in
                if b.isHeading {
                    Text(b.text).font(.serif(20)).tracking(-0.2).padding(.top, 6)
                } else {
                    paragraph(b.text)
                }
            }
        }
        .frame(maxWidth: 620, alignment: .leading)
        .textSelection(.enabled)
    }

    private func paragraph(_ t: String) -> some View {
        Text(t).font(.serif(17, .regular)).lineSpacing(7).foregroundStyle(T.ink2)
            .frame(maxWidth: 620, alignment: .leading)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button { store.saveArticle(item); saved = true } label: {
                Text(saved ? "Kaydedildi ✓" : "Defterime kaydet").font(.ui(12.5, .semibold)).foregroundStyle(T.accentInk)
                    .padding(.horizontal, 14).padding(.vertical, 8).background(T.accent, in: RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(.plain)
            BookmarkButton(item: item)
            Button { if let l = item.link { store.openWeb(GoogleNews.cached(l) ?? l) } } label: {
                Text("Kaynakta aç ↗").font(.ui(12.5, .medium))
                    .padding(.horizontal, 14).padding(.vertical, 8).background(T.paper, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(T.rule, lineWidth: 1))
            }.buttonStyle(.plain)
        }.padding(.top, 6)
    }
}

/// Adds the story to Arşiv or takes it out; filled icon and accent outline while it's archived.
struct BookmarkButton: View {
    @Environment(AppStore.self) private var store
    let item: NewsItem
    var body: some View {
        let on = store.isBookmarked(item.id)
        Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { store.toggleBookmark(item) } } label: {
            HStack(spacing: 6) {
                Image(systemName: on ? "bookmark.fill" : "bookmark").font(.system(size: 11, weight: .semibold))
                    .symbolEffect(.bounce, value: on)
                Text(on ? "Arşivde" : "Arşive ekle").font(.ui(12.5, .medium))
            }
            .foregroundStyle(on ? T.accent : T.ink)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(on ? T.accentSoft : T.paper, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(on ? T.accent.opacity(0.5) : T.rule, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(on ? "Arşivden çıkar" : "Arşive ekle")
    }
}
