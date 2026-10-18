import SwiftUI
import CoreLocation

// MARK: - Provinces and districts

/// The 81 provinces and their districts, with Turkish spellings (Resources/districts.json, made by scripts/make_districts.py).
enum Districts {
    static let all: [String: [String]] = {
        guard let u = Bundle.main.url(forResource: "districts", withExtension: "json"),
              let d = try? JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: u)) else { return [:] }
        return d
    }()

    static func of(_ province: String) -> [String] { all[province] ?? [] }

    /// The district of `province` written as `name` in any spelling ("SALIHLI", "Salihli"), if there is one.
    static func match(_ name: String?, in province: String) -> String? {
        guard let name, !name.isEmpty else { return nil }
        let f = Provinces.fold(name)
        return of(province).first { Provinces.fold($0) == f }
    }

    /// A free-text place (the weather city) as province and district: "Manisa" → (Manisa, nil),
    /// "Salihli" → (Manisa, Salihli). Names shared by several provinces ("Merkez", "Yeşilyurt") give no district.
    static func place(_ text: String) -> (province: String, district: String?)? {
        let f = Provinces.fold(text)
        if let p = Provinces.all.first(where: { Provinces.fold($0) == f }) { return (p, nil) }
        let hits = all.filter { $0.value.contains { Provinces.fold($0) == f } }
        if hits.count == 1, let (p, ds) = hits.first { return (p, ds.first { Provinces.fold($0) == f }) }
        if let p = Provinces.match(text) { return (p, nil) }
        return nil
    }
}

// MARK: - Google News (search feed and link decoding)

enum GoogleNews {
    private static let safariUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    /// Last week's stories mentioning the place, newest first. A district is searched together with its province
    /// ("Yunusemre" alone also brings Eskişehir's and people named so); a "Merkez" district means the province itself.
    static func local(province: String, district: String?) async throws -> [NewsItem] {
        let q = district.map { "\"\($0)\" \"\(province)\"" } ?? "\"\(province)\""
        var c = URLComponents(string: "https://news.google.com/rss/search")!
        c.queryItems = [.init(name: "q", value: q + " when:7d"), .init(name: "hl", value: "tr"),
                        .init(name: "gl", value: "TR"), .init(name: "ceid", value: "TR:tr")]
        let src = NewsSource(id: "yerel", name: "Google Haberler", url: c.url!.absoluteString, defaultCategory: "Yerel", blurb: "Yerel")
        return try await NewsService.fetch(src).map(split).sorted { $0.date > $1.date }
    }

    /// Google writes "Başlık - Kaynak" and a description that only repeats it: take the outlet from the title.
    private static func split(_ n: NewsItem) -> NewsItem {
        var title = n.title, source = n.source
        if let r = title.range(of: " - ", options: .backwards) {
            source = String(title[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            title = String(title[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return NewsItem(id: n.id, sourceID: n.sourceID, source: source, category: "Yerel", title: title, summary: "",
                        link: n.link, imageURL: nil, date: n.date)
    }

    /// No stored cookies, and consent already given: with Google's own cookies (set while the feed loads) the article
    /// page turns into a "Before you continue" consent screen without the signature.
    private static let plain: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        c.httpCookieAcceptPolicy = .never
        c.httpAdditionalHeaders = ["User-Agent": safariUA, "Cookie": "SOCS=CAI", "Accept-Language": "tr-TR,tr;q=0.9"]
        return URLSession(configuration: c)
    }()

    @MainActor private static var resolved: [URL: URL] = [:]

    /// The publisher's own address for a news.google.com/rss/articles/… link, once looked up.
    @MainActor static func cached(_ url: URL) -> URL? { resolved[url] }

    /// news.google.com/rss/articles/<id> only redirects with JavaScript. Its page carries a signature and timestamp;
    /// posting those back (the "garturlreq" call Google's own page makes) returns the real URL.
    @MainActor static func resolve(_ url: URL) async -> URL? {
        if let r = resolved[url] { return r }
        guard url.host == "news.google.com", let id = url.pathComponents.last,
              let (page, _) = try? await plain.data(from: url) else { return nil }
        let html = String(decoding: page, as: UTF8.self)
        func attr(_ name: String) -> String? {
            guard let r = html.range(of: name + "=\""), let end = html[r.upperBound...].firstIndex(of: "\"") else { return nil }
            return String(html[r.upperBound..<end])
        }
        guard let sg = attr("data-n-a-sg"), let ts = attr("data-n-a-ts").flatMap(Int.init) else { return nil }
        let inner: [Any] = ["garturlreq", [["X", "X", ["X", "X"], NSNull(), NSNull(), 1, 1, "US:en", NSNull(), 1, NSNull(), NSNull(),
                                             NSNull(), NSNull(), NSNull(), 0, 1], "X", "X", 1, [1, 1, 1], 1, 1, NSNull(), 0, 0, NSNull(), 0],
                            id, ts, sg]
        guard let innerData = try? JSONSerialization.data(withJSONObject: inner),
              let outer = try? JSONSerialization.data(withJSONObject: [[["Fbv4je", String(decoding: innerData, as: UTF8.self), NSNull(), "generic"]]]),
              let api = URL(string: "https://news.google.com/_/DotsSplashUi/data/batchexecute") else { return nil }
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        var req = URLRequest(url: api)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(("f.req=" + (String(decoding: outer, as: UTF8.self).addingPercentEncoding(withAllowedCharacters: allowed) ?? "")).utf8)
        // reply: )]}'  then  [["wrb.fr","Fbv4je","[\"garturlres\",\"https://…\",1]",…],…]
        guard let (data, _) = try? await plain.data(for: req) else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        guard let start = text.firstIndex(of: "["),
              let rows = try? JSONSerialization.jsonObject(with: Data(text[start...].utf8)) as? [Any],
              let row = rows.first as? [Any], row.count > 2, let payload = row[2] as? String,
              let res = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [Any],
              res.count > 1, let s = res[1] as? String, let real = URL(string: s), real.scheme?.hasPrefix("http") == true else { return nil }
        resolved[url] = real
        return real
    }
}

// MARK: - Device location

enum LocationError: LocalizedError {
    case denied, unavailable
    var errorDescription: String? {
        switch self {
        case .denied: return isPhone ? "Konum izni yok. Ayarlar › Gizlilik ve Güvenlik › Konum Servisleri › PANO'dan izin ver."
                             : "Konum izni yok. Sistem Ayarları › Gizlilik ve Güvenlik › Konum Servisleri'nden PANO'ya izin ver."
        case .unavailable: return "Konum bulunamadı. İli ve ilçeyi menüden seçebilirsin."
        }
    }
}

/// One-shot "where am I": the Mac's location (Wi-Fi based) reverse-geocoded to a province and district.
@MainActor
enum DeviceLocation {
    private static let manager = CLLocationManager()

    static func place() async throws -> (province: String, district: String?) {
        switch manager.authorizationStatus {
        case .denied, .restricted: throw LocationError.denied
        case .notDetermined: manager.requestWhenInUseAuthorization()
        default: break
        }
        let location = try await withThrowingTaskGroup(of: CLLocation?.self) { group in
            group.addTask {
                for try await u in CLLocationUpdate.liveUpdates() {
                    if let l = u.location { return l }
                }
                return nil
            }
            group.addTask { try await Task.sleep(nanoseconds: 20_000_000_000); return nil }
            let first = try await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let location else {
            if [.denied, .restricted].contains(manager.authorizationStatus) { throw LocationError.denied }
            throw LocationError.unavailable
        }
        let marks = try? await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "tr_TR"))
        guard let m = marks?.first, let province = Provinces.match(m.administrativeArea ?? "") ?? Provinces.match(m.locality ?? "")
        else { throw LocationError.unavailable }
        let district = [m.subAdministrativeArea, m.locality, m.subLocality].lazy.compactMap { Districts.match($0, in: province) }.first
        return (province, district)
    }
}

// MARK: - Store

/// Yerel: news of one province or district. The place is picked from the menus, found from the Mac's location,
/// or, until either happens, taken from the weather city.
@MainActor @Observable
final class YerelStore {
    /// nil until the user picks or locates a place; the weather city stands in meanwhile.
    var province: String? = UserDefaults.standard.string(forKey: "yerelProvince") {
        didSet { UserDefaults.standard.set(province, forKey: "yerelProvince") }
    }
    var district: String? = UserDefaults.standard.string(forKey: "yerelDistrict") {
        didSet { UserDefaults.standard.set(district, forKey: "yerelDistrict") }
    }
    /// The place came from the device location (shown with a pin).
    var located = UserDefaults.standard.bool(forKey: "yerelLocated") {
        didSet { UserDefaults.standard.set(located, forKey: "yerelLocated") }
    }
    var items: [NewsItem] = []
    var state: LoadState = .idle
    var query = ""
    var selectedID: String?
    var locating = false
    var locateError: String?
    @ObservationIgnored private var cache: [String: (at: Date, items: [NewsItem])] = [:]

    /// The place in use: the chosen one, else the weather city's.
    func place(weatherCity: String) -> (province: String, district: String?) {
        if let province { return (province, district) }
        return Districts.place(weatherCity) ?? ("İstanbul", nil)
    }

    func pick(_ province: String, _ district: String?) {
        self.province = province; self.district = district; located = false; locateError = nil
    }

    func locate() async {
        locating = true; locateError = nil
        defer { locating = false }
        do {
            let p = try await DeviceLocation.place()
            province = p.province; district = p.district; located = true
        } catch {
            locateError = error.localizedDescription
        }
    }

    /// Lists are kept for 15 minutes per place; `force` refetches.
    func load(_ p: (province: String, district: String?), force: Bool = false) async {
        // "Merkez" is the central district of a smaller province: its news is the province's
        let district = p.district == "Merkez" ? nil : p.district
        let key = p.province + "|" + (district ?? "")
        if !force, let c = cache[key], Date().timeIntervalSince(c.at) < 900 { items = c.items; state = .loaded; return }
        if cache[key] == nil { items = []; selectedID = nil }
        state = .loading
        do {
            let list = try await GoogleNews.local(province: p.province, district: district)
            guard !Task.isCancelled else { return }
            cache[key] = (Date(), list); items = list; state = .loaded
        } catch {
            guard !Task.isCancelled else { return }
            if let c = cache[key] { items = c.items; state = .loaded }
            else { state = .failed(error is ServiceError ? "Bu yer için haber bulunamadı." : "Haberler alınamadı.") }
        }
    }

    var filtered: [NewsItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? items : items.filter { $0.mentions(q) || $0.source.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    var selected: NewsItem? {
        let list = filtered
        return list.first { $0.id == selectedID } ?? list.first
    }
}

// MARK: - View

/// Yerel tab: the news of the user's province or district — same two-pane reading as Haberler.
struct YerelView: View {
    @Environment(AppStore.self) private var store

    private var yerel: YerelStore { store.yerel }
    private var place: (province: String, district: String?) { yerel.place(weatherCity: store.prefs.cityName) }
    private var placeKey: String { place.province + "|" + (place.district ?? "") }
    private var placeName: String { place.district.map { "\($0), \(place.province)" } ?? place.province }

    var body: some View {
        @Bindable var yerel = yerel
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Yerel").font(.serif(25)).tracking(-0.4)
                    Spacer()
                    Text(yerel.query.trimmingCharacters(in: .whitespaces).isEmpty
                         ? "\(yerel.filtered.count) başlık · son 7 gün · Google Haberler"
                         : "\(yerel.filtered.count) sonuç").font(.mono(11, .regular)).foregroundStyle(T.ink3)
                }
                if isPhone {
                    HStack(spacing: 8) { provinceMenu; districtMenu; locateButton }.phoneScroll()
                    searchField
                } else {
                    HStack(spacing: 8) {
                        provinceMenu
                        districtMenu
                        locateButton
                        Spacer(minLength: 8)
                        searchField
                    }
                }
                if let e = yerel.locateError {
                    Text(e).font(.ui(11.5)).foregroundStyle(T.down)
                }
            }
            .padding(.screenHeader)
            .overlay(alignment: .bottom) { Rule() }

            content
        }
        .task(id: placeKey) { yerel.query = ""; await yerel.load(place) }
        .task {
            // first visit: try the device location once; the weather city stands in if that fails
            guard yerel.province == nil, !UserDefaults.standard.bool(forKey: "yerelAskedLocation") else { return }
            UserDefaults.standard.set(true, forKey: "yerelAskedLocation")
            await yerel.locate()
            yerel.locateError = nil
        }
    }

    private var searchField: some View {
        @Bindable var yerel = yerel
        return HStack(spacing: 6) {
                        Text("⌕").font(.ui(13)).foregroundStyle(T.ink3)
            TextField("\(place.district ?? place.province) haberlerinde ara", text: $yerel.query)
                .textFieldStyle(.plain).font(.ui(12.5)).frame(width: isPhone ? nil : 190)
            if !yerel.query.isEmpty {
                Button { yerel.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(T.ink3)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(T.paper2, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(T.rule, lineWidth: 1))
    }

    private func chip(_ text: String) -> some View {
        Text(text).font(.ui(12)).foregroundStyle(T.ink2).lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(T.paper2, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(T.rule, lineWidth: 1))
    }

    private var provinceMenu: some View {
        Menu {
            let weather = Districts.place(store.prefs.cityName)
            if let w = weather {
                Button("Hava durumu şehri (\(w.district ?? w.province))") { yerel.pick(w.province, w.district) }
                Divider()
            }
            ForEach(Provinces.all, id: \.self) { p in Button(p) { yerel.pick(p, nil) } }
        } label: {
            chip("İl: \(place.province) ▾")
        }.menuStyle(.button).buttonStyle(.plain).fixedSize().help("İl seç")
    }

    private var districtMenu: some View {
        Menu {
            Button("\(place.province) geneli") { yerel.pick(place.province, nil) }
            Divider()
            ForEach(Districts.of(place.province), id: \.self) { d in Button(d) { yerel.pick(place.province, d) } }
        } label: {
            chip("İlçe: \(place.district ?? "Tümü") ▾")
        }.menuStyle(.button).buttonStyle(.plain).fixedSize().help("İlçe seç")
    }

    private var locateButton: some View {
        Button { Task { await yerel.locate() } } label: {
            HStack(spacing: 5) {
                if yerel.locating { ProgressView().controlSize(.mini) }
                else { Image(systemName: yerel.located ? "location.fill" : "location").font(.system(size: 11)) }
                Text(yerel.locating ? "Konum aranıyor…" : "Konumum").font(.ui(12))
            }
            .foregroundStyle(yerel.located ? T.accent : T.ink2)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(yerel.located ? T.accentSoft : T.paper2, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(yerel.located ? T.accent.opacity(0.4) : T.rule, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(yerel.locating)
        .help(yerel.located ? "Konumundan bulundu: \(placeName). Yeniden bulmak için tıkla." : "Bulunduğun il ve ilçeyi konumundan bul")
    }

    @ViewBuilder private var content: some View {
        let list = yerel.filtered
        if case .failed(let m) = yerel.state, yerel.items.isEmpty {
            ErrorCard(eyebrow: "HATA · YEREL", message: m) { Task { await yerel.load(place, force: true) } }
                .frame(maxWidth: 340).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if yerel.items.isEmpty, yerel.state != .loaded {
            SkeletonCard(title: "YÜKLENİYOR · \(placeName.uppercased(with: Locale(identifier: "tr_TR")))", widths: [0.8, 0.95, 0.6, 0.9, 0.7])
                .frame(maxWidth: 340).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if list.isEmpty {
            let searching = !yerel.query.trimmingCharacters(in: .whitespaces).isEmpty
            EmptyBox(title: searching ? "“\(yerel.query)” için sonuç yok" : "\(placeName) için son bir haftada haber yok",
                     subtitle: searching ? "Başka bir kelime dene" : "İl geneline bakmayı dene")
                .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            NewsFeedPane(items: list, selected: yerel.selected, fold: false) { yerel.selectedID = $0.id }
        }
    }
}
