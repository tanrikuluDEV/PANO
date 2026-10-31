import SwiftUI
import AppKit

/// ⌘K: one box that finds anything — a tab, a story, an archived story, a match, a radio station, a TV channel or a
/// Defter entry — and goes there. ↑↓ choose, ↩ opens, Esc (or a click outside) closes.
struct QuickSearchView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool
    /// ↑ ↓ ↩ Esc: an NSTextField keeps those keys to itself, so they're caught before it sees them.
    @State private var keyMonitor: Any?
    /// The monitor is installed once, but must act on what's on screen now: each redraw hands it a fresh handler.
    private final class KeyHandler { var handle: (UInt16) -> Bool = { _ in false } }
    @State private var keys = KeyHandler()

    struct Hit: Identifiable {
        let id: String
        let section: String
        let icon: String
        let title: String
        let detail: String
        let action: () -> Void
    }

    private var hits: [Hit] {
        let raw = query.trimmingCharacters(in: .whitespaces)
        let q = Search.fold(raw)
        let s = store
        var out: [Hit] = []

        let screens = Screen.allCases.filter { q.isEmpty || Search.fold($0.rawValue).contains(q) }
        out += screens.map { sc in
            Hit(id: "screen-\(sc.rawValue)", section: "SEKMELER", icon: sc.symbol, title: sc.rawValue, detail: "Sekmeye git") {
                s.screen = sc
            }
        }
        guard q.count >= 2 else { return out }

        // headlines that say it first, then stories that only mention it in the summary
        var inTitle: [NewsItem] = [], inSummary: [NewsItem] = []
        for n in s.visibleNews where inTitle.count < 6 {
            switch s.searchRank(n, q) {
            case 0: inTitle.append(n)
            case 1: if inSummary.count < 6 { inSummary.append(n) }
            default: break
            }
        }
        out += (inTitle + inSummary).prefix(6).map { n in
            Hit(id: "news-\(n.id)", section: "HABERLER", icon: "newspaper", title: n.title,
                detail: "\(n.source) · \(Day.relativeName(n.date)) \(Day.hm(n.date))") { s.openNews(n) }
        }
        out += s.bookmarks.lazy.map(\.item).filter { s.matchesSearch($0, q) }.prefix(3).map { n in
            Hit(id: "arsiv-\(n.id)", section: "ARŞİV", icon: "bookmark", title: n.title, detail: n.source) {
                s.arsivQuery = ""; s.selectedArsivID = n.id; s.screen = .arsiv
            }
        }
        let games = s.matches.values.joined().filter { Search.fold($0.home + " " + $0.away + " " + $0.league).contains(q) }
            .sorted { abs($0.kickoff.timeIntervalSinceNow) < abs($1.kickoff.timeIntervalSinceNow) }
        out += games.prefix(3).map { m in
            Hit(id: "match-\(m.id)", section: "MAÇLAR", icon: "soccerball", title: "\(m.home) – \(m.away)",
                detail: "\(m.league) · \(m.kind == .upcoming ? Day.relativeName(m.kickoff) + " " + Day.hm(m.kickoff) : m.scoreText + " · " + m.statusText)") {
                s.footballLiveOnly = false; s.footballDay = Day.key(m.kickoff); s.selectedMatchID = m.id; s.screen = .futbol
                Task { await s.refreshFootball() }
            }
        }
        var seenStations = Set<String>()
        let stations = (s.radio.stations + s.radio.allLocal).filter { Search.fold($0.name).contains(q) && seenStations.insert($0.id).inserted }
        out += stations.prefix(4).map { st in
            Hit(id: "radio-\(st.id)", section: "RADYO", icon: "dot.radiowaves.left.and.right", title: st.name,
                detail: s.radio.current?.id == st.id ? "Çalıyor" : "Çal") { s.radio.play(st) }
        }
        out += s.tv.channels.filter { Search.fold($0.name).contains(q) }.prefix(4).map { c in
            Hit(id: "tv-\(c.id)", section: "CANLI TV", icon: "tv", title: c.name, detail: c.category) {
                s.screen = .canliTV; s.tv.play(c)
            }
        }
        let notes = s.journal.values.filter { Search.fold($0.text + " " + $0.tags.joined(separator: " ")).contains(q) }
            .sorted { $0.day > $1.day }
        out += notes.prefix(3).map { e in
            Hit(id: "defter-\(e.day)", section: "DEFTER", icon: "book.closed", title: snippet(e.text, around: raw),
                detail: Day.date(e.day).map(Day.long) ?? e.day) {
                s.journalDay = e.day; s.screen = .defter
            }
        }
        return out
    }

    /// The line of the note that contains the search term (else its first line).
    private func snippet(_ text: String, around term: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        let q = Search.fold(term)
        let line = lines.first { Search.fold($0).contains(q) } ?? lines.first ?? ""
        return line.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        let hits = hits
        let _ = keys.handle = { code in
            switch code {
            case 125: move(1, hits.count)                 // ↓
            case 126: move(-1, hits.count)                // ↑
            case 36, 76: open(hits)                       // ↩ / enter
            case 53: close()                              // esc
            default: return false
            }
            return true
        }
        ZStack(alignment: .top) {
            Color.black.opacity(0.12).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { close() }
            VStack(spacing: 0) {
                field(hits)
                Rule()
                results(hits)
                footer
            }
            .frame(width: 600)
            .background { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial) }
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(T.rule, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.28), radius: 40, y: 18)
            .padding(.top, 110)
        }
        .onAppear {
            focused = true
            let keys = keys
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in keys.handle(e.keyCode) ? nil : e }
        }
        .onDisappear { if let m = keyMonitor { NSEvent.removeMonitor(m) }; keyMonitor = nil }
        .onChange(of: query) { selected = 0 }
    }

    private func field(_ hits: [Hit]) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 16)).foregroundStyle(T.ink3)
            TextField("Haber, sekme, kanal, takım, not ara", text: $query)
                .textFieldStyle(.plain).font(.ui(17))
                .focused($focused)
            Text("esc").font(.mono(10)).foregroundStyle(T.ink3)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(T.rule, lineWidth: 1))
        }
        .padding(.horizontal, 18).padding(.vertical, 15)
    }

    private func results(_ hits: [Hit]) -> some View {
        Group {
            if hits.isEmpty {
                Text("“\(query.trimmingCharacters(in: .whitespaces))” için sonuç yok")
                    .font(.ui(13)).foregroundStyle(T.ink3).frame(maxWidth: .infinity).padding(.vertical, 28)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(hits.enumerated()), id: \.element.id) { i, h in
                                if i == 0 || hits[i - 1].section != h.section {
                                    Eyebrow(text: h.section, size: 9.5).padding(.horizontal, 18).padding(.top, i == 0 ? 10 : 14).padding(.bottom, 4)
                                }
                                row(h, selected: i == selected).id(h.id)
                                    .onTapGesture { selected = i; open(hits) }
                            }
                        }
                        .padding(.bottom, 8)
                    }
                    .frame(maxHeight: 420)
                    .onChange(of: selected) { _, i in
                        if hits.indices.contains(i) { proxy.scrollTo(hits[i].id, anchor: nil) }
                    }
                }
            }
        }
    }

    private func row(_ h: Hit, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: h.icon).font(.system(size: 13)).frame(width: 20)
                .foregroundStyle(selected ? T.accent : T.ink2)
            VStack(alignment: .leading, spacing: 2) {
                Text(h.title).font(.ui(13.5, selected ? .medium : .regular)).foregroundStyle(T.ink).lineLimit(1)
                Text(h.detail).font(.mono(10.5, .regular)).foregroundStyle(T.ink3).lineLimit(1)
            }
            Spacer(minLength: 8)
            if selected { Text("↩").font(.ui(13)).foregroundStyle(T.ink3) }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(selected ? T.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text("↑↓ seç").font(.mono(10, .regular))
            Text("↩ aç").font(.mono(10, .regular))
            Text("esc kapat").font(.mono(10, .regular))
            Spacer()
            Text("⌘K").font(.mono(10, .regular))
        }
        .foregroundStyle(T.ink3)
        .padding(.horizontal, 18).padding(.vertical, 9)
        .overlay(alignment: .top) { Rule() }
    }

    private func move(_ d: Int, _ count: Int) {
        guard count > 0 else { return }
        selected = (selected + d + count) % count
    }

    private func open(_ hits: [Hit]) {
        guard hits.indices.contains(selected) else { close(); return }
        let h = hits[selected]
        close()
        h.action()
    }

    private func close() { withAnimation(.easeOut(duration: 0.15)) { store.quickSearchOpen = false } }
}
