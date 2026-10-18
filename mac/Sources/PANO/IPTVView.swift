import SwiftUI

// MARK: - Store

struct IPTVCountry: Codable, Identifiable, Hashable {
    let code: String      // iptv-org's code; the United Kingdom is "UK", not ISO's "GB"
    let name: String      // Turkish name when macOS knows the region, else iptv-org's English one
    let flag: String
    var id: String { code }
}

/// IPTV: every list in iptv-org (https://github.com/iptv-org/iptv), by country or by category.
/// A source is "c:<country>", "k:<category>" or "fav". Lists are fetched when picked and kept for the session;
/// the country list is cached on disk.
@MainActor @Observable
final class IPTVStore {
    var countries: [IPTVCountry] = Storage.load([IPTVCountry].self, "iptv-countries.json") ?? []
    var source: String = UserDefaults.standard.string(forKey: "iptvSource") ?? "k:news" {
        didSet { UserDefaults.standard.set(source, forKey: "iptvSource") }
    }
    var channels: [TVChannel] = []
    var state: LoadState = .idle
    /// Stream URLs found dead this session; those channels are left out of the lists.
    var dead = Set<String>()
    /// Progress of the stream check for the current list (nil when it's done).
    var checking: (done: Int, total: Int)?
    @ObservationIgnored private var cache: [String: [TVChannel]] = [:]
    @ObservationIgnored private var checked = Set<String>()

    /// The current list without channels whose stream is known to be dead.
    var liveChannels: [TVChannel] { channels.filter { !dead.contains($0.url) } }

    /// iptv-org categories in menu order; "xxx" is left out.
    static let categories = ["news", "sports", "movies", "series", "entertainment", "music", "kids", "animation", "documentary",
                             "science", "culture", "education", "travel", "outdoor", "cooking", "lifestyle", "comedy", "classic",
                             "family", "business", "auto", "religious", "weather", "relax", "legislative", "public", "general",
                             "shop", "interactive"]

    func loadCountries() async {
        guard countries.isEmpty, let url = URL(string: "https://iptv-org.github.io/api/countries.json") else { return }
        struct Raw: Decodable { let name: String; let code: String; let flag: String? }
        guard let data = try? await fetch(url), let raws = try? JSONDecoder().decode([Raw].self, from: data) else { return }
        let tr = Locale(identifier: "tr_TR")
        countries = raws.map { r in
            let iso = r.code == "UK" ? "GB" : r.code
            return IPTVCountry(code: r.code, name: tr.localizedString(forRegionCode: iso) ?? r.name, flag: r.flag ?? "🏳️")
        }
        .sorted { $0.name.compare($1.name, locale: tr) == .orderedAscending }
        Storage.save(countries, "iptv-countries.json")
    }

    func load() async {
        let key = source
        guard key != "fav" else { state = .loaded; return }
        if let c = cache[key] { channels = c; state = .loaded; return }
        channels = []; state = .loading
        let path = key.hasPrefix("c:") ? "countries/\(key.dropFirst(2).lowercased()).m3u" : "categories/\(key.dropFirst(2)).m3u"
        do {
            guard let url = URL(string: "https://iptv-org.github.io/iptv/" + path) else { throw ServiceError.empty }
            let list = try await TVService.load(url, turkish: false)
            guard key == source else { return }
            cache[key] = list; channels = list; state = .loaded
        } catch {
            guard key == source else { return }
            state = .failed("Kanal listesi alınamadı.")
        }
    }

    /// Try every not-yet-checked stream of the current list, 24 at a time; dead ones drop out of the list when the
    /// check ends (not one by one, so the list doesn't shift under the pointer). Cancelled when the list changes.
    func checkStreams() async {
        guard source != "fav" else { checking = nil; return }
        let todo = channels.filter { !checked.contains($0.url) }
        guard !todo.isEmpty else { checking = nil; return }
        checking = (0, todo.count)
        var found = Set<String>(), done = 0
        await withTaskGroup(of: (String, Bool).self) { group in
            var next = todo.makeIterator()
            for _ in 0..<24 { if let c = next.next() { group.addTask { (c.url, await TVService.isAlive(c)) } } }
            for await (url, alive) in group {
                if Task.isCancelled { group.cancelAll(); return }
                checked.insert(url); if !alive { found.insert(url) }
                done += 1; checking = (done, todo.count)
                if let c = next.next() { group.addTask { (c.url, await TVService.isAlive(c)) } }
            }
        }
        dead.formUnion(found)
        if !Task.isCancelled { checking = nil }
    }

    func title(_ key: String) -> String {
        if key == "fav" { return "♥ Favoriler" }
        if key.hasPrefix("k:") { return TVService.categoryNames[String(key.dropFirst(2))] ?? String(key.dropFirst(2)) }
        let code = String(key.dropFirst(2)).uppercased()
        return countries.first { $0.code == code }.map { "\($0.flag) \($0.name)" } ?? code
    }
}

// MARK: - View

/// IPTV tab: pick a country or a category from iptv-org, then a channel. Same player as Canlı TV (mini player,
/// sleep timer, radio hand-off), with category chips inside the list and search.
struct IPTVView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var group = "Tümü"

    private var iptv: IPTVStore { store.iptv }

    private var pool: [TVChannel] { iptv.source == "fav" ? store.tv.favoriteChannels : iptv.liveChannels }

    private var status: String {
        if iptv.source != "fav", let c = iptv.checking { return "\(pool.count) kanal · yayınlar deneniyor \(c.done)/\(c.total)" }
        let off = iptv.source == "fav" ? 0 : iptv.channels.count - pool.count
        return off > 0 ? "\(pool.count) kanal · \(off) kapalı yayın gizlendi" : "\(pool.count) kanal · iptv-org"
    }

    private var list: [TVChannel] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return pool.filter { c in
            if !q.isEmpty { return c.name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            return group == "Tümü" || c.category == group
        }
    }

    /// Categories present in the current list, most channels first (only useful for a country list).
    private var groups: [String] {
        let counts = Dictionary(grouping: pool, by: \.category).mapValues(\.count)
        return ["Tümü"] + counts.keys.sorted { (counts[$0] ?? 0, $1) > (counts[$1] ?? 0, $0) }
    }

    var body: some View {
        let list = list
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("IPTV").font(.serif(25)).tracking(-0.4)
                sourceMenu
                Spacer()
                Text(status).font(.mono(11, .regular)).foregroundStyle(T.ink3)
                    .help("iptv-org'daki yayınların bir kısmı kapalı; açılmayanlar denenip listeden çıkarılır.")
            }
            .padding(.init(top: 34, leading: 24, bottom: 14, trailing: 24))
            .overlay(alignment: .bottom) { Rule() }

            HStack(spacing: 0) {
                TVPlayerPane().frame(maxWidth: .infinity, maxHeight: .infinity)
                channelColumn(list).frame(width: 320).overlay(alignment: .leading) { VRule() }
            }
        }
        .task { await iptv.loadCountries() }
        .task(id: iptv.source) { group = "Tümü"; query = ""; await iptv.load(); await iptv.checkStreams() }
        .onAppear { DispatchQueue.main.async { store.tv.ensurePlaying() } }
    }

    private var sourceMenu: some View {
        Menu {
            Button("♥ Favoriler") { iptv.source = "fav" }
            Divider()
            Menu("Kategoriye göre") {
                ForEach(IPTVStore.categories, id: \.self) { k in
                    Button(TVService.categoryNames[k] ?? k) { iptv.source = "k:" + k }
                }
            }
            Menu("Ülkeye göre") {
                if iptv.countries.isEmpty { Text("Ülkeler yükleniyor…") }
                ForEach(iptv.countries) { c in
                    Button("\(c.flag) \(c.name)") { iptv.source = "c:" + c.code.lowercased() }
                }
            }
        } label: {
            Text("\(iptv.title(iptv.source)) ▾").font(.ui(12.5, .medium)).foregroundStyle(T.accent).lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(T.accentSoft, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(T.accent.opacity(0.4), lineWidth: 1))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("Kategori ya da ülke seç")
    }

    private func channelColumn(_ list: [TVChannel]) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                ChannelSearchField(query: $query)
                if groups.count > 2 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(groups, id: \.self) { g in
                                Button { group = g } label: { Pill(text: g, selected: g == group) }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(12)
            .overlay(alignment: .bottom) { Rule() }

            if iptv.source != "fav", case .failed(let m) = iptv.state {
                ErrorCard(eyebrow: "HATA · IPTV", message: m) { Task { await iptv.load(); await iptv.checkStreams() } }.padding(16)
                Spacer()
            } else if iptv.source != "fav", iptv.state == .loading {
                SkeletonCard(title: "YÜKLENİYOR · KANALLAR").padding(16)
                Spacer()
            } else if list.isEmpty {
                EmptyBox(title: iptv.source == "fav" && query.isEmpty ? "Henüz favori kanal yok" : "Kanal bulunamadı",
                         subtitle: iptv.source == "fav" && query.isEmpty ? "İzlerken ♡'ye basarak ekle" : "Başka bir liste ya da arama dene").padding(16)
                Spacer()
            } else {
                ChannelList(channels: list)
            }
        }
    }
}
