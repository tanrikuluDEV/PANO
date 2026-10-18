import Foundation
import AVFoundation
import AVKit

// MARK: - Model

struct TVChannel: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let url: String
    let logo: String?
    let category: String
    /// Extra request headers some streams need (from the playlist's #EXTVLCOPT lines).
    let headers: [String: String]
    /// Only reachable from Türkiye.
    let geoBlocked: Bool
    /// Not on air around the clock.
    let partTime: Bool
    /// Position in the "Ulusal" list; nil for everything else.
    let rank: Int?
}

let tvCategories = ["Tümü", "Favoriler", "Ulusal", "Haber", "Spor", "Çocuk", "Müzik", "Belgesel & Kültür", "Dini", "Yerel & Diğer"]

// MARK: - Directory (iptv-org, the open list of freely available streams)

enum TVService {
    private static let turkeyList = URL(string: "https://iptv-org.github.io/iptv/countries/tr.m3u")!

    /// The big national channels, in the order they're listed under "Ulusal" and at the top of "Tümü".
    private static let majors = ["TRT 1", "ATV", "Kanal D", "Star TV", "NOW", "TV8", "TRT Haber", "NTV", "Habertürk", "Halk TV",
                                 "A Haber", "TGRT Haber", "Haber Global", "24 TV", "TRT Spor", "A Spor", "TRT Çocuk", "TRT 2",
                                 "TRT Belgesel", "360", "Ekotürk", "Euro D"]

    /// The playlist spells many names without Turkish letters. Applied in order (an array, not a dictionary,
    /// whose order isn't fixed). Tags in brackets are already gone by then, so "ATV (Turkiye)" is just "ATV".
    private static let nameFixes: [(String, String)] = [("Haberturk", "Habertürk"), ("Cocuk", "Çocuk"), ("Ekoturk", "Ekotürk"),
                                                        ("Ilkokul", "İlkokul"), ("Turkiye", "Türkiye"), ("Muzik", "Müzik"),
                                                        ("Yildiz", "Yıldız")]

    /// iptv-org group titles in Turkish, for the world lists (IPTV tab).
    static let categoryNames: [String: String] = [
        "animation": "Animasyon", "auto": "Otomobil", "business": "Ekonomi", "classic": "Klasik", "comedy": "Komedi",
        "cooking": "Yemek", "culture": "Kültür", "documentary": "Belgesel", "education": "Eğitim", "entertainment": "Eğlence",
        "family": "Aile", "general": "Genel", "interactive": "Etkileşimli", "kids": "Çocuk", "legislative": "Meclis",
        "lifestyle": "Yaşam", "movies": "Film", "music": "Müzik", "news": "Haber", "outdoor": "Doğa", "public": "Kamu",
        "relax": "Rahatlama", "religious": "Dini", "series": "Dizi", "science": "Bilim", "shop": "Alışveriş",
        "sports": "Spor", "travel": "Seyahat", "weather": "Hava durumu"]

    /// The Türkiye list for Canlı TV.
    static func load() async throws -> [TVChannel] { try await load(turkeyList, turkish: true) }

    /// Any iptv-org playlist. `turkish`: the Türkiye list, which gets Turkish name fixes, its own categories and
    /// the Ulusal ranking; world lists keep their names and get translated iptv-org categories. Adult channels are left out.
    static func load(_ playlist: URL, turkish: Bool) async throws -> [TVChannel] {
        let text = String(decoding: try await fetch(playlist), as: UTF8.self)
        var out: [TVChannel] = []
        var info: String?
        var headers: [String: String] = [:]
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXTINF") { info = line; headers = [:] }
            else if line.hasPrefix("#EXTVLCOPT:http-referrer=") { headers["Referer"] = String(line.dropFirst("#EXTVLCOPT:http-referrer=".count)) }
            else if line.hasPrefix("#EXTVLCOPT:http-user-agent=") { headers["User-Agent"] = String(line.dropFirst("#EXTVLCOPT:http-user-agent=".count)) }
            else if !line.isEmpty, !line.hasPrefix("#"), let i = info {
                if let c = channel(info: i, url: line, headers: headers, turkish: turkish) { out.append(c) }
                info = nil
            }
        }
        // one entry per name: keep the first (the playlist lists the best feed first)
        var seen = Set<String>()
        return out.filter { seen.insert($0.name.lowercased()).inserted }
            .sorted { ($0.rank ?? 999, $0.name) < ($1.rank ?? 999, $1.name) }
    }

    private static func attr(_ key: String, in s: String) -> String? {
        guard let r = s.range(of: "\(key)=\""), let end = s[r.upperBound...].firstIndex(of: "\"") else { return nil }
        let v = String(s[r.upperBound..<end]); return v.isEmpty ? nil : v
    }

    private static func channel(info: String, url: String, headers: [String: String], turkish: Bool) -> TVChannel? {
        guard let comma = info.lastIndex(of: ",") else { return nil }
        let group = attr("group-title", in: info) ?? ""
        if group.lowercased().contains("xxx") { return nil }
        var name = String(info[info.index(after: comma)...])
        let geo = name.contains("[Geo-blocked]"), part = name.contains("[Not 24/7]")
        // drop "(1080p)", "[Not 24/7]" and similar tags
        name = name.replacingOccurrences(of: "\\s*[\\(\\[][^\\)\\]]*[\\)\\]]", with: "", options: .regularExpression)
        if turkish { for (a, b) in nameFixes { name = name.replacingOccurrences(of: a, with: b) } }
        name = name.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
        if name.hasSuffix(" SD") || name.hasSuffix(" HD") { name = String(name.dropLast(3)) }
        guard !name.isEmpty else { return nil }
        let rank: Int? = turkish
            ? majors.firstIndex(where: { name == $0 || name.hasPrefix($0 + " ") && !name.contains("Avrupa") && !name.contains("Alanya") })
            : nil
        return TVChannel(id: attr("tvg-id", in: info) ?? name, name: name, url: url, logo: attr("tvg-logo", in: info),
                         category: turkish ? category(group, name: name) : worldCategory(group), headers: headers,
                         geoBlocked: geo, partTime: part, rank: rank)
    }

    private static let probeSession: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 8
        c.httpAdditionalHeaders = ["User-Agent": "AppleCoreMedia/1.0.0 (Macintosh; U; Intel Mac OS X 15_0; tr_tr)"]
        return URLSession(configuration: c)
    }()

    /// Whether a stream answers: its playlist (and the first variant of a master playlist) loads. About a third of
    /// iptv-org's streams are dead at any time (404, gone hosts, bad certificates); this catches nearly all of them.
    static func isAlive(_ c: TVChannel) async -> Bool {
        guard var url = URL(string: c.url), url.scheme?.hasPrefix("http") == true, !c.url.contains(".mpd") else { return false }
        for _ in 0..<3 {
            guard let (final, head) = await peek(url, headers: c.headers) else { return false }
            let text = String(decoding: head.prefix(8000), as: UTF8.self)
            guard text.contains("#EXTM3U") else { return head.count > 1000 }   // a raw stream (MPEG-TS and the like)
            guard text.contains("#EXT-X-STREAM-INF") else { return true }
            guard let line = text.components(separatedBy: .newlines).map({ $0.trimmingCharacters(in: .whitespaces) })
                    .first(where: { !$0.isEmpty && !$0.hasPrefix("#") }),
                  let next = URL(string: line, relativeTo: final)?.absoluteURL else { return false }
            url = next
        }
        return false
    }

    /// The first 64 KB of a response (a live stream would never end) and the URL it came from after redirects.
    private static func peek(_ url: URL, headers: [String: String]) async -> (URL, Data)? {
        var req = URLRequest(url: url)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        guard let (bytes, resp) = try? await probeSession.bytes(for: req),
              let h = resp as? HTTPURLResponse, (200..<300).contains(h.statusCode) else { return nil }
        var data = Data()
        do { for try await b in bytes { data.append(b); if data.count >= 65_536 { break } } } catch { if data.isEmpty { return nil } }
        return (h.url ?? url, data)
    }

    /// "News;Politics" → "Haber"; unknown or "Undefined" → "Diğer".
    private static func worldCategory(_ group: String) -> String {
        group.lowercased().split(separator: ";").lazy.compactMap { categoryNames[String($0).trimmingCharacters(in: .whitespaces)] }.first ?? "Diğer"
    }

    private static func category(_ group: String, name: String) -> String {
        let g = group.lowercased()
        if g.contains("news") { return "Haber" }
        if g.contains("sport") { return "Spor" }
        if g.contains("kids") || g.contains("animation") { return "Çocuk" }
        if g.contains("music") { return "Müzik" }
        if g.contains("religious") { return "Dini" }
        if g.contains("documentary") || g.contains("culture") || g.contains("education") || g.contains("travel") { return "Belgesel & Kültür" }
        let n = name.lowercased()
        if n.contains("haber") { return "Haber" }
        if n.contains("spor") { return "Spor" }
        return "Yerel & Diğer"
    }
}

// MARK: - Player

enum TVState: Equatable { case idle, loading, playing, failed(String) }

@MainActor @Observable
final class TVStore {
    var channels: [TVChannel] = Storage.load([TVChannel].self, "tv.json") ?? []
    var loadState: LoadState = .idle
    var current: TVChannel?
    var state: TVState = .idle
    var favorites: [String] = UserDefaults.standard.stringArray(forKey: "tvFavorites") ?? []
    /// Channels that failed to open this session, dimmed in the list.
    var failed = Set<String>()
    @ObservationIgnored let player = AVPlayer()
    /// True while the Canlı TV or IPTV tab is showing (set by AppStore as screens change).
    @ObservationIgnored var onTVTab = false
    /// Called when a channel starts, so the radio can stop (never both at once).
    @ObservationIgnored var onStart: (() -> Void)?
    @ObservationIgnored private var observers: [NSKeyValueObservation] = []
    @ObservationIgnored private var requestID = 0
    @ObservationIgnored private var lastLoad = UserDefaults.standard.object(forKey: "tvLoaded") as? Date ?? .distantPast

    /// Refetch the channel list at most once a day (streams move, channels come and go).
    func loadIfNeeded() async {
        guard channels.isEmpty || Date().timeIntervalSince(lastLoad) > 86_400 else { return }
        if channels.isEmpty { loadState = .loading }
        do {
            channels = try await TVService.load()
            loadState = .loaded
            lastLoad = Date(); UserDefaults.standard.set(lastLoad, forKey: "tvLoaded")
            Storage.save(channels, "tv.json")
        } catch {
            loadState = channels.isEmpty ? .failed("Kanal listesi alınamadı.") : .loaded
        }
    }

    /// Full copies of favourited channels, so favourites from any IPTV list stay playable without reloading it.
    var favoriteChannels: [TVChannel] = Storage.load([TVChannel].self, "tv-favorites.json") ?? []

    func isFavorite(_ c: TVChannel) -> Bool { favorites.contains(c.id) }
    func toggleFavorite(_ c: TVChannel) {
        if let i = favorites.firstIndex(of: c.id) {
            favorites.remove(at: i)
            favoriteChannels.removeAll { $0.id == c.id }
        } else {
            favorites.append(c.id)
            favoriteChannels.append(c)
        }
        UserDefaults.standard.set(favorites, forKey: "tvFavorites")
        Storage.save(favoriteChannels, "tv-favorites.json")
    }

    func play(_ c: TVChannel) {
        guard let url = URL(string: c.url) else { return }
        onStart?()
        requestID += 1
        let id = requestID
        current = c; state = .loading; failed.remove(c.id)
        var options: [String: Any] = [:]
        if !c.headers.isEmpty { options["AVURLAssetHTTPHeaderFieldsKey"] = c.headers }
        let item = AVPlayerItem(asset: AVURLAsset(url: url, options: options))
        observers = [
            item.observe(\.status) { [weak self] it, _ in
                guard it.status == .failed else { return }
                Task { @MainActor in self?.fail(c, id: id) }
            },
            player.observe(\.timeControlStatus) { [weak self] p, _ in
                let st = p.timeControlStatus
                Task { @MainActor in
                    guard let self, id == self.requestID else { return }
                    if st == .playing { self.state = .playing }
                    else if st == .waitingToPlayAtSpecifiedRate, self.state != .playing { self.state = .loading }
                    // Paused from the video's own controls while the Canlı TV tab is showing: treat it as ■ Stop,
                    // so the mini player doesn't appear on other tabs and nothing restarts on its own. A pause
                    // while another tab is open comes from the big player being torn down, and is ignored.
                    else if st == .paused, self.onTVTab, self.state == .playing { self.stop() }
                }
            },
        ]
        player.replaceCurrentItem(with: item)
        player.play()
        Task {
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            if id == requestID, state == .loading { fail(c, id: id) }
        }
    }

    private func fail(_ c: TVChannel, id: Int) {
        guard id == requestID else { return }
        player.replaceCurrentItem(with: nil)
        failed.insert(c.id)
        state = .failed(c.geoBlocked ? "Bu kanal bölge kısıtlı; yalnızca kendi ülkesinden izlenebiliyor olabilir."
                                     : "Yayın şu an açılamıyor. Başka bir kanal dene.")
    }

    /// The big and mini players hand the same AVPlayer back and forth as tabs change; if tearing one view down
    /// paused it, pick playback back up.
    func ensurePlaying() {
        if (state == .playing || state == .loading), player.currentItem != nil, player.rate == 0 { player.play() }
    }

    /// Stop and drop the stream (live TV: the next play starts at the live point, like the radio).
    func stop() {
        requestID += 1
        player.pause(); player.replaceCurrentItem(with: nil)
        observers.removeAll()
        if current != nil { state = .idle }
    }
}
