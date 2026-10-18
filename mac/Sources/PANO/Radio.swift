import Foundation
import AVFoundation
import MediaPlayer

// MARK: - Model

struct Station: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let url: String
    let logo: String?
    let tags: String
    let codec: String
    let bitrate: Int
    let votes: Int
    let category: String
    /// Province the station broadcasts from, when its directory entry says so (see `Provinces.match`).
    var province: String? = nil
    /// FM frequency (and district) for bundled local stations, e.g. "90.8" or "91.0 · Salihli".
    var freq: String? = nil

    var initials: String {
        let words = name.split(separator: " ").filter { $0.first?.isLetter == true }
        return String(words.prefix(2).compactMap { $0.first }).uppercased()
    }
    var detail: String {
        var parts = (freq.map { ["FM \($0)"] } ?? []) + [category]
        if bitrate > 0 { parts.append("\(bitrate) kbps") }
        return parts.joined(separator: " · ")
    }
}

let radioCategories = ["Tümü", "Favoriler", "Yerel", "Haber", "Pop", "Türkü & Halk", "Nostalji", "Arabesk", "Rock", "Diğer"]

private func categorize(name: String, tags: String) -> String {
    let s = (name + " " + tags).lowercased()
    func has(_ w: [String]) -> Bool { w.contains { s.contains($0) } }
    if has(["haber", "news", "ntv", "cnn", "bloomberg", "habertürk", "a haber", "ekonomi"]) { return "Haber" }
    if has(["türkü", "turku", "folk", "halk", "yöresel", "ankara havalari", "bozlak"]) { return "Türkü & Halk" }
    if has(["arabesk", "fantezi", "damar", "slow türk", "slow turk"]) { return "Arabesk" }
    if has(["nostalj", "retro", "oldies", "70s", "80s", "90s", "altın", "45lik", "doksan", "golden", "klasik", "classical", "sanat"]) { return "Nostalji" }
    if has(["rock", "metal", "alternatif", "alternative", "indie"]) { return "Rock" }
    if has(["pop", "top 40", "hit", "dance"]) { return "Pop" }
    return "Diğer"
}

// MARK: - Provinces (for local radio)

/// Türkiye's 81 provinces, and matching a free-text place (a station's state / name / tags, the weather city)
/// to one of them. Matching is on whole words with Turkish letters folded to ASCII, since directory entries
/// are written every which way ("Istanbul", "İSTANBUL", "Istambul", "istanbul bagcılar").
enum Provinces {
    static let all = ["Adana", "Adıyaman", "Afyonkarahisar", "Ağrı", "Aksaray", "Amasya", "Ankara", "Antalya", "Ardahan", "Artvin",
        "Aydın", "Balıkesir", "Bartın", "Batman", "Bayburt", "Bilecik", "Bingöl", "Bitlis", "Bolu", "Burdur", "Bursa", "Çanakkale",
        "Çankırı", "Çorum", "Denizli", "Diyarbakır", "Düzce", "Edirne", "Elazığ", "Erzincan", "Erzurum", "Eskişehir", "Gaziantep",
        "Giresun", "Gümüşhane", "Hakkari", "Hatay", "Iğdır", "Isparta", "İstanbul", "İzmir", "Kahramanmaraş", "Karabük", "Karaman",
        "Kars", "Kastamonu", "Kayseri", "Kilis", "Kırıkkale", "Kırklareli", "Kırşehir", "Kocaeli", "Konya", "Kütahya", "Malatya",
        "Manisa", "Mardin", "Mersin", "Muğla", "Muş", "Nevşehir", "Niğde", "Ordu", "Osmaniye", "Rize", "Sakarya", "Samsun", "Siirt",
        "Sinop", "Sivas", "Şanlıurfa", "Şırnak", "Tekirdağ", "Tokat", "Trabzon", "Tunceli", "Uşak", "Van", "Yalova", "Yozgat", "Zonguldak"]

    /// Old names, short forms and the districts local stations most often name instead of their province.
    private static let aliases: [String: [String]] = [
        "İstanbul": ["istambul", "uskudar", "kadikoy", "bagcilar", "besiktas", "beyoglu", "fatih", "esenyurt", "pendik", "kartal", "bakirkoy", "sisli"],
        "Mersin": ["icel", "tarsus", "silifke"], "Kahramanmaraş": ["maras"], "Şanlıurfa": ["urfa"], "Afyonkarahisar": ["afyon"],
        "Hatay": ["antakya", "iskenderun", "samandag", "defne"], "Kocaeli": ["izmit", "gebze"], "Sakarya": ["adapazari"],
        "Balıkesir": ["bandirma", "edremit", "ayvalik", "gonen"], "Samsun": ["bafra", "carsamba"], "Bitlis": ["tatvan", "ahlat", "guroymak"],
        "Muğla": ["bodrum", "fethiye", "marmaris", "milas"], "Antalya": ["alanya", "manavgat", "kemer"], "Aydın": ["kusadasi", "didim", "nazilli"],
        "Çanakkale": ["gokceada", "biga"], "Giresun": ["espiye"], "Van": ["gevas", "ercis"], "Bursa": ["inegol", "yenisehir", "gemlik"],
        "Konya": ["eregli", "aksehir"], "Ankara": ["polatli"], "İzmir": ["karsiyaka", "bornova", "odemis"], "Adana": ["ceyhan", "kozan"],
        "Tunceli": ["dersim"], "Trabzon": ["akcaabat"], "Ordu": ["fatsa", "unye"],
    ]

    static func fold(_ s: String) -> String {
        s.replacingOccurrences(of: "İ", with: "i").replacingOccurrences(of: "I", with: "ı").lowercased()
            .replacingOccurrences(of: "ı", with: "i")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "tr_TR"))
    }

    private static let patterns: [(String, NSRegularExpression)] = all.compactMap { p in
        let keys = [fold(p)] + (aliases[p] ?? [])
        let alt = keys.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        return (try? NSRegularExpression(pattern: "(^|[^a-z])(\(alt))([^a-z]|$)")).map { (p, $0) }
    }

    /// First province named in `text`, if any.
    static func match(_ text: String) -> String? {
        let t = fold(text)
        let r = NSRange(t.startIndex..., in: t)
        return patterns.first { $0.1.firstMatch(in: t, range: r) != nil }?.0
    }

    /// Turkish alphabetical order (Ç after C, İ after I, Ş after S …).
    static func sorted(_ names: [String]) -> [String] {
        names.sorted { $0.compare($1, locale: Locale(identifier: "tr_TR")) == .orderedAscending }
    }
}

// MARK: - Directory (radio-browser.info, community API, no key)

enum RadioService {
    private struct Raw: Decodable {
        let stationuuid: String
        let name: String
        let url: String
        let url_resolved: String
        let favicon: String
        let tags: String
        let codec: String
        let bitrate: Int
        let votes: Int
        let lastcheckok: Int
        let state: String?
    }

    private static let hosts = ["de1", "de2", "all"]

    private static func query(_ extra: String) async throws -> [Station] {
        var lastError: Error = ServiceError.empty
        for h in hosts {
            let u = "https://\(h).api.radio-browser.info/json/stations/search?countrycode=TR&hidebroken=true&order=clickcount&reverse=true&\(extra)"
            guard let url = URL(string: u) else { continue }
            do {
                let raws = try JSONDecoder().decode([Raw].self, from: try await fetch(url))
                return raws.compactMap(station)
            } catch { lastError = error }
        }
        throw lastError
    }

    private static func station(_ r: Raw) -> Station? {
        let codec = r.codec.uppercased()
        guard r.lastcheckok == 1, !codec.contains("OGG"), !codec.contains("FLAC") else { return nil }
        let url = r.url_resolved.isEmpty ? r.url : r.url_resolved
        let name = r.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, !name.isEmpty, !name.lowercased().contains("test") else { return nil }
        // the directory's own place field first, then the station name, then its tags
        let province = [r.state ?? "", name, r.tags].lazy.compactMap { Provinces.match($0) }.first
        return Station(id: r.stationuuid, name: name, url: url, logo: r.favicon.isEmpty ? nil : r.favicon, tags: r.tags,
                       codec: r.codec, bitrate: r.bitrate, votes: r.votes, category: categorize(name: name, tags: r.tags),
                       province: province)
    }

    /// Top Turkish stations plus a few well-known names the popularity list tends to miss.
    static func load() async throws -> [Station] {
        let extras = ["trt", "best fm", "radyo d", "cnn", "bloomberg", "habertürk", "eksen", "slow", "virgin", "power", "kral", "metro", "joy"]
        var all = try await query("limit=300")
        await withTaskGroup(of: [Station].self) { g in
            for e in extras {
                let enc = e.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? e
                g.addTask { (try? await query("limit=6&name=\(enc)")) ?? [] }
            }
            for await r in g { all += r }
        }
        var best: [String: Station] = [:]
        for s in all {
            let key = s.name.lowercased().filter { $0.isLetter || $0.isNumber }
            if let old = best[key], old.votes >= s.votes { continue }
            best[key] = s
        }
        return best.values.sorted { $0.votes > $1.votes }
    }

    /// Local stations bundled with the app (Resources/local-stations.json, made by scripts/fetch_local_stations.py)
    /// for provinces the live directory barely covers. Each was checked to be streaming when the file was made.
    static let bundledLocal: [Station] = {
        struct B: Decodable { let id, name, url, province: String; let logo, freq: String? }
        guard let u = Bundle.main.url(forResource: "local-stations", withExtension: "json"),
              let list = try? JSONDecoder().decode([B].self, from: Data(contentsOf: u)) else { return [] }
        return list.map { b in
            Station(id: b.id, name: b.name, url: b.url, logo: b.logo, tags: "", codec: "", bitrate: 0, votes: 0,
                    category: categorize(name: b.name, tags: ""), province: b.province, freq: b.freq)
        }
    }()

    /// Every Turkish station tied to a province — local stations rarely make the popularity top 300.
    static func loadLocal() async throws -> [Station] {
        var best: [String: Station] = [:]
        for s in try await query("limit=5000") where s.province != nil {
            let key = s.name.lowercased().filter { $0.isLetter || $0.isNumber } + "|" + (s.province ?? "")
            if let old = best[key], old.votes >= s.votes { continue }
            best[key] = s
        }
        return best.values.sorted { $0.votes > $1.votes }
    }

    static func search(_ text: String) async -> [Station] {
        let enc = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        return (try? await query("limit=60&name=\(enc)")) ?? []
    }

    /// `.pls` / `.m3u` playlists are not playable by AVPlayer directly — pull the first stream URL out.
    static func playableURL(_ s: Station) async -> (url: URL, mime: String?)? {
        guard let url = URL(string: s.url) else { return nil }
        let ext = url.pathExtension.lowercased()
        guard ext == "pls" || ext == "m3u" else { return (url, nil) }
        // Some ".pls" URLs are really the audio stream itself, so only look at the first KB.
        var head = Data()
        var mime: String?
        do {
            let (bytes, resp) = try await session.bytes(from: url)
            mime = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.components(separatedBy: ";").first
            for try await b in bytes { head.append(b); if head.count >= 2048 { break } }
        } catch { return (url, nil) }
        guard let text = String(data: head, encoding: .utf8), text.contains("[playlist]") || text.hasPrefix("#EXTM3U") || text.lowercased().hasPrefix("http") else {
            // not a playlist: the URL is the audio stream, AVPlayer just needs to be told its type
            return (url, mime?.hasPrefix("audio/") == true ? (mime == "audio/aacp" ? "audio/aac" : mime) : "audio/mpeg")
        }
        for line in text.components(separatedBy: .newlines) {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.lowercased().hasPrefix("file"), let eq = l.firstIndex(of: "="), let u = URL(string: String(l[l.index(after: eq)...])) { return (u, nil) }
            if l.lowercased().hasPrefix("http"), let u = URL(string: l) { return (u, nil) }
        }
        return (url, nil)
    }
}

// MARK: - Player

/// `stopped`: a station is still selected (the bar stays up) but its stream is dropped, so ▶ reconnects to the
/// live broadcast instead of resuming a stale buffer. `idle`: nothing selected, the bar is gone.
enum PlayState: Equatable { case idle, loading, playing, stopped, failed(String) }

@MainActor @Observable
final class RadioStore: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    var stations: [Station] = Storage.load([Station].self, "radio.json") ?? []
    var loadState: LoadState = .idle
    var favorites: [String] = UserDefaults.standard.stringArray(forKey: "radioFavorites") ?? []
    var current: Station?
    var state: PlayState = .idle
    var nowPlaying: String?
    /// The song now on air (nil for slogans, ads and stations that send nothing), with cover and link once found.
    var currentSong: PlayedSong?
    /// Radyo › Çalanlar, newest first, capped at 300.
    var songHistory: [PlayedSong] = Storage.load([PlayedSong].self, "radio-history.json") ?? []
    var volume: Double = UserDefaults.standard.object(forKey: "radioVolume") as? Double ?? 0.8 {
        didSet { player.volume = Float(volume); UserDefaults.standard.set(volume, forKey: "radioVolume") }
    }
    var searchResults: [Station] = []
    /// Stations tied to a province, for the Yerel filter; fetched the first time Yerel is opened.
    var localStations: [Station] = Storage.load([Station].self, "radio-local.json") ?? [] {
        didSet { rebuildLocal() }
    }
    /// Directory stations plus the bundled list; a bundled station replaces a directory one of the same name in
    /// the same city (it carries the frequency and a checked stream). Alphabetical, since popularity votes mean
    /// little for small local stations. Built only when `localStations` changes — folding names and a Turkish
    /// sort are too slow to repeat on every redraw.
    private(set) var allLocal: [Station] = []
    /// Provinces that have at least one station, with how many.
    private(set) var localCounts: [String: Int] = [:]

    private func rebuildLocal() {
        func key(_ s: Station) -> String { Provinces.fold(s.name).filter(\.isLetter) + "|" + (s.province ?? "") }
        let bundled = RadioService.bundledLocal
        let taken = Set(bundled.map(key))
        let tr = Locale(identifier: "tr_TR")
        allLocal = (bundled + localStations.filter { !taken.contains(key($0)) })
            .sorted { $0.name.compare($1.name, locale: tr) == .orderedAscending }
        localCounts = Dictionary(grouping: allLocal) { $0.province ?? "" }.mapValues(\.count)
    }
    var localState: LoadState = .idle
    /// Province picked under Yerel (nil until the user picks one; the view then defaults to the weather city).
    var localCity: String? = UserDefaults.standard.string(forKey: "radioLocalCity") {
        didSet { UserDefaults.standard.set(localCity, forKey: "radioLocalCity") }
    }

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var observers: [NSKeyValueObservation] = []
    @ObservationIgnored private var retries = 0
    @ObservationIgnored private var requestID = 0
    /// Called when a station starts (AppStore stops the TV with it).
    @ObservationIgnored var onStart: (() -> Void)?

    override init() {
        super.init()
        player.volume = Float(volume)
        rebuildLocal()
        if let id = UserDefaults.standard.string(forKey: "radioLast") { current = stations.first { $0.id == id } }
        setupRemote()
    }

    var isPlaying: Bool { state == .playing || state == .loading }

    func loadStations() async {
        if stations.isEmpty { loadState = .loading }
        do {
            let list = try await RadioService.load()
            stations = list
            loadState = .loaded
            Storage.save(list, "radio.json")
            if let c = current, let fresh = list.first(where: { $0.id == c.id }) { current = fresh }
        } catch {
            if stations.isEmpty { loadState = .failed("Radyo listesi alınamadı.") }
        }
    }

    func loadLocal() async {
        if localStations.isEmpty { localState = .loading }
        do {
            let list = try await RadioService.loadLocal()
            localStations = list
            localState = .loaded
            Storage.save(list, "radio-local.json")
        } catch {
            localState = localStations.isEmpty ? .failed("Yerel radyo listesi alınamadı.") : .loaded
        }
    }

    func search(_ text: String) async {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2 else { searchResults = []; return }
        let r = await RadioService.search(t)
        if !Task.isCancelled { searchResults = r }
    }

    // MARK: Favorites

    func isFavorite(_ s: Station) -> Bool { favorites.contains(s.id) }
    func toggleFavorite(_ s: Station) {
        if let i = favorites.firstIndex(of: s.id) { favorites.remove(at: i) } else { favorites.append(s.id) }
        UserDefaults.standard.set(favorites, forKey: "radioFavorites")
        if !stations.contains(where: { $0.id == s.id }) { stations.append(s) }   // keep searched favourites listable
    }

    // MARK: Playback

    func play(_ s: Station) {
        current = s
        UserDefaults.standard.set(s.id, forKey: "radioLast")
        retries = 0
        start(s)
    }

    /// Scales the output under the user's volume (sleep-timer fade); 1 = normal.
    func fade(_ f: Double) {
        let v = Float(volume * f)
        if player.volume != v { player.volume = v }
    }

    /// Stop / play. Live radio has nothing to resume: ▶ always starts the stream afresh, at the live point.
    func toggle() {
        switch state {
        case .playing, .loading: halt()
        default: if let c = current { play(c) }
        }
    }

    /// Stop playback but keep the station selected. The item is dropped, not paused, so nothing keeps
    /// buffering in the background and the next ▶ comes back live.
    func halt() {
        requestID += 1
        player.pause(); player.replaceCurrentItem(with: nil)
        observers.removeAll(); nowPlaying = nil; currentSong = nil; state = .stopped; updateInfo()
    }

    /// Close the radio altogether: nothing selected, the now-playing bar goes away.
    func stop() {
        requestID += 1
        player.pause(); player.replaceCurrentItem(with: nil)
        observers.removeAll(); nowPlaying = nil; currentSong = nil; state = .idle; updateInfo()
    }

    func step(_ delta: Int, in list: [Station]) {
        guard let c = current, let i = list.firstIndex(of: c), !list.isEmpty else { if let f = list.first { play(f) }; return }
        play(list[(i + delta + list.count) % list.count])
    }

    private func start(_ s: Station) {
        onStart?()
        requestID += 1
        let id = requestID
        state = .loading; nowPlaying = nil; currentSong = nil
        observers.removeAll()
        Task {
            guard let src = await RadioService.playableURL(s), id == requestID else { return }
            let asset = src.mime.map { AVURLAsset(url: src.url, options: ["AVURLAssetOutOfBandMIMETypeKey": $0]) } ?? AVURLAsset(url: src.url)
            let item = AVPlayerItem(asset: asset)
            let out = AVPlayerItemMetadataOutput(identifiers: nil)
            out.setDelegate(self, queue: .main)
            item.add(out)
            observers = [
                item.observe(\.status) { [weak self] it, _ in
                    guard it.status == .failed else { return }
                    let msg = it.error?.localizedDescription ?? "Yayın açılamadı."
                    Task { @MainActor in self?.failed(msg, station: s, id: id) }
                },
                player.observe(\.timeControlStatus) { [weak self] p, _ in
                    let st = p.timeControlStatus
                    Task { @MainActor in
                        guard let self, id == self.requestID else { return }
                        switch st {
                        case .playing: self.state = .playing; self.retries = 0; self.updateInfo()
                        case .waitingToPlayAtSpecifiedRate: if self.state != .stopped { self.state = .loading }
                        default: break
                        }
                    }
                }
            ]
            player.replaceCurrentItem(with: item)
            player.play()
            updateInfo()
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            if id == requestID, state == .loading { state = .failed("Yayın açılamadı. Başka bir kanal dene.") }
        }
    }

    private func failed(_ msg: String, station: Station, id: Int) {
        guard id == requestID else { return }
        if retries < 2 {
            retries += 1
            Task { try? await Task.sleep(nanoseconds: 1_500_000_000); if id == requestID { start(station) } }
        } else {
            state = .failed("Yayın açılamadı. Başka bir kanal dene.")
            NSLog("radio failed: \(msg)")
        }
    }

    // ICY "StreamTitle" (artist – song) arrives as timed metadata.
    nonisolated func metadataOutput(_ output: AVPlayerItemMetadataOutput, didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup], from track: AVPlayerItemTrack?) {
        guard let item = groups.flatMap({ $0.items }).first(where: { $0.identifier == .icyMetadataStreamTitle || $0.commonKey == .commonKeyTitle }) else { return }
        Task { @MainActor in
            let title = try? await item.load(.stringValue)
            let t = title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let new = (t?.isEmpty ?? true) ? nil : t
            guard new != self.nowPlaying else { return }
            self.nowPlaying = new
            self.updateInfo()
            self.songChanged(new)
        }
    }

    // MARK: Song history

    private func songChanged(_ text: String?) {
        guard let text, let s = current, SongLookup.isSong(text, station: s.name) else { currentSong = nil; return }
        let song = PlayedSong(text: text, station: s.name, date: Date())
        currentSong = song
        // the same song again on the same station soon after (a stream reconnect) isn't a new play
        let repeatPlay = songHistory.first.map { $0.text == text && $0.station == s.name && Date().timeIntervalSince($0.date) < 3 * 3600 } ?? false
        if !repeatPlay {
            songHistory.insert(song, at: 0)
            if songHistory.count > 300 { songHistory.removeLast(songHistory.count - 300) }
        }
        Task {
            let full = await SongLookup.enrich(song)
            if currentSong?.id == song.id { currentSong = full }
            if let i = songHistory.firstIndex(where: { $0.id == song.id }) { songHistory[i] = full }
            Storage.save(songHistory, "radio-history.json")
        }
    }

    func clearSongHistory() {
        songHistory = []
        Storage.save(songHistory, "radio-history.json")
    }

    // MARK: Media keys / Now Playing

    private func setupRemote() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in Task { @MainActor in if self?.state != .playing { self?.toggle() } }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in if self?.isPlaying == true { self?.halt() } }; return .success }
        c.stopCommand.addTarget { [weak self] _ in Task { @MainActor in if self?.isPlaying == true { self?.halt() } }; return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
    }

    private func updateInfo() {
        guard let c = current, state != .idle else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        var info: [String: Any] = [MPMediaItemPropertyTitle: nowPlaying ?? c.name, MPMediaItemPropertyArtist: c.name,
                                   MPNowPlayingInfoPropertyIsLiveStream: true,
                                   MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0]
        if nowPlaying == nil { info[MPMediaItemPropertyArtist] = "PANO Radyo" }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
