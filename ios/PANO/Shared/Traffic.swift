import SwiftUI
import MapKit

/// Yol Durumu: Apple Maps' live traffic layer plus driving times for a few saved routes. Each route's time now is
/// compared with the same drive at 03:00 (free-flowing), which gives the delay and the Akıcı / Yoğun label.
/// MapKit needs no key; Apple has traffic data for Turkish cities.
struct TrafficRoute: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    let from: String
    let to: String
    let fromLat: Double, fromLon: Double
    let toLat: Double, toLon: Double

    var title: String { "\(from) → \(to)" }
    var source: CLLocationCoordinate2D { .init(latitude: fromLat, longitude: fromLon) }
    var destination: CLLocationCoordinate2D { .init(latitude: toLat, longitude: toLon) }

    static func make(_ from: String, _ a: (Double, Double), _ to: String, _ b: (Double, Double)) -> TrafficRoute {
        TrafficRoute(from: from, to: to, fromLat: a.0, fromLon: a.1, toLat: b.0, toLon: b.1)
    }
}

enum TrafficLevel {
    case akici, yogun, cokYogun
    init(now: Double, typical: Double) {
        let r = now / max(typical, 1)
        self = r < 1.15 ? .akici : r < 1.4 ? .yogun : .cokYogun
    }
    var label: String { switch self { case .akici: "Akıcı"; case .yogun: "Yoğun"; case .cokYogun: "Çok yoğun" } }
    var color: Color { switch self { case .akici: T.up; case .yogun: Color.orange; case .cokYogun: T.down } }
}

struct RouteStatus {
    let minutes: Double
    let typical: Double
    let distanceKm: Double
    let road: String
    let hasTolls: Bool
    let polyline: MKPolyline
    let updated: Date
    var delay: Int { max(0, Int((minutes - typical).rounded())) }
    var level: TrafficLevel { TrafficLevel(now: minutes, typical: typical) }
}

/// Ready-made routes for the cities the app is mostly used in; offered under "Hazır rotalar" and seeded once.
enum RoutePresets {
    private static let konak = (38.4189, 27.1287), karsiyaka = (38.4555, 27.1172), bornova = (38.4697, 27.2211)
    private static let alsancak = (38.4370, 27.1428), buca = (38.3886, 27.1750), cigli = (38.4969, 27.0735)
    private static let havalimani = (38.2924, 27.1570), manisa = (38.6140, 27.4296), turgutlu = (38.4963, 27.7007)
    private static let akhisar = (38.9185, 27.8386), salihli = (38.4826, 28.1392)

    static let izmir: [TrafficRoute] = [
        .make("Karşıyaka", karsiyaka, "Konak", konak),
        .make("Bornova", bornova, "Alsancak", alsancak),
        .make("Buca", buca, "Çiğli", cigli),
        .make("Konak", konak, "Havalimanı", havalimani),
        .make("İzmir", konak, "Manisa", manisa),
    ]
    static let manisaList: [TrafficRoute] = [
        .make("Manisa", manisa, "İzmir", konak),
        .make("Manisa", manisa, "Turgutlu", turgutlu),
        .make("Manisa", manisa, "Akhisar", akhisar),
        .make("Manisa", manisa, "Salihli", salihli),
    ]
    static func forCity(_ province: String?) -> [TrafficRoute] {
        switch province { case "İzmir": izmir; case "Manisa": manisaList; default: [] }
    }
}

@MainActor @Observable
final class TrafficStore {
    var routes: [TrafficRoute] = Storage.load([TrafficRoute].self, "routes.json") ?? [] {
        didSet { Storage.save(routes, "routes.json") }
    }
    var status: [String: RouteStatus] = [:]
    var failed: Set<String> = []
    var busy = false
    var lastRefresh: Date?
    /// Free-flow time per route, worked out once a day.
    @ObservationIgnored private var typical: [String: (day: String, minutes: Double)] = [:]

    /// First visit: fill in the weather city's ready-made routes (İzmir, Manisa); later visits leave the list alone.
    func seedIfNeeded(city: String) {
        guard !UserDefaults.standard.bool(forKey: "routesSeeded") else { return }
        UserDefaults.standard.set(true, forKey: "routesSeeded")
        if routes.isEmpty { routes = RoutePresets.forCity(Provinces.match(city)) }
    }

    /// Every five minutes at most, unless forced; one route at a time so Apple's rate limit isn't hit.
    func refresh(force: Bool = false) async {
        guard !busy, force || lastRefresh.map({ Date().timeIntervalSince($0) > 300 }) ?? true else { return }
        busy = true
        defer { busy = false; lastRefresh = Date() }
        for r in routes {
            guard let now = try? await Self.drive(r, at: nil) else { failed.insert(r.id); continue }
            failed.remove(r.id)
            let base = await typicalMinutes(r) ?? now.expectedTravelTime / 60
            status[r.id] = RouteStatus(minutes: now.expectedTravelTime / 60, typical: min(base, now.expectedTravelTime / 60),
                                       distanceKm: now.distance / 1000, road: now.name, hasTolls: now.hasTolls,
                                       polyline: now.polyline, updated: Date())
        }
    }

    private func typicalMinutes(_ r: TrafficRoute) async -> Double? {
        let day = Day.key()
        if let t = typical[r.id], t.day == day { return t.minutes }
        let tomorrow = Day.cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        guard let night = Day.cal.date(bySettingHour: 3, minute: 0, second: 0, of: tomorrow),
              let route = try? await Self.drive(r, at: night) else { return nil }
        typical[r.id] = (day, route.expectedTravelTime / 60)
        return route.expectedTravelTime / 60
    }

    private static func drive(_ r: TrafficRoute, at date: Date?) async throws -> MKRoute {
        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: r.source))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: r.destination))
        req.transportType = .automobile
        if let date { req.departureDate = date }
        guard let route = try await MKDirections(request: req).calculate().routes.first else { throw ServiceError.empty }
        return route
    }

    /// Looks both places up near the city ("Ev" won't work, "Bornova Metro" will) and adds the route.
    func add(from: String, to: String, near center: CLLocationCoordinate2D) async throws {
        async let a = Self.place(from, near: center)
        async let b = Self.place(to, near: center)
        let (pa, pb) = try await (a, b)
        let r = TrafficRoute(from: from, to: to, fromLat: pa.latitude, fromLon: pa.longitude, toLat: pb.latitude, toLon: pb.longitude)
        routes.append(r)
        await refresh(force: true)
    }

    func add(_ preset: TrafficRoute) async {
        guard !routes.contains(where: { $0.title == preset.title }) else { return }
        routes.append(TrafficRoute(from: preset.from, to: preset.to, fromLat: preset.fromLat, fromLon: preset.fromLon,
                                   toLat: preset.toLat, toLon: preset.toLon))
        await refresh(force: true)
    }

    func remove(_ r: TrafficRoute) {
        routes.removeAll { $0.id == r.id }
        status[r.id] = nil
    }

    private static func place(_ text: String, near center: CLLocationCoordinate2D) async throws -> CLLocationCoordinate2D {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = text
        req.region = MKCoordinateRegion(center: center, span: .init(latitudeDelta: 1.2, longitudeDelta: 1.2))
        guard let item = try await MKLocalSearch(request: req).start().mapItems.first else { throw TrafficError.notFound(text) }
        return item.placemark.coordinate
    }

    enum TrafficError: LocalizedError {
        case notFound(String)
        var errorDescription: String? { switch self { case .notFound(let t): "“\(t)” bulunamadı. Semt ya da yer adıyla dene." } }
    }

    static func openInMaps(_ r: TrafficRoute) {
        let a = MKMapItem(placemark: MKPlacemark(coordinate: r.source)); a.name = r.from
        let b = MKMapItem(placemark: MKPlacemark(coordinate: r.destination)); b.name = r.to
        MKMapItem.openMaps(with: [a, b], launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}

extension AppStore {
    /// Traffic stories from the news pool: accidents, closures, jams — in the weather city first.
    var trafficNews: [NewsItem] {
        let words = ["trafik", "kaza", "zincirleme", "yol kapa", "ulaşıma kapa", "trafiğe kapa", "çevre yolu", "otoyol", "köprü", "tünel", "yol çalışma"]
        let pool = visibleNews.filter { n in words.contains { n.mentions($0) } && n.category != "Spor" }
        let prov = Provinces.match(prefs.cityName) ?? prefs.cityName
        let local = pool.filter { $0.mentions(prov) }
        return local.count >= 3 ? local : local + pool.filter { !$0.mentions(prov) }.prefix(8 - min(local.count, 8))
    }
}

// MARK: - Screen

struct YolDurumuView: View {
    @Environment(AppStore.self) private var store
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedID: String?
    @State private var from = ""
    @State private var to = ""
    @State private var adding = false
    @State private var addError: String?
    /// Route being dragged to a new place in the list (Bugün follows the same order).
    @State private var dragging: TrafficRoute?

    private var traffic: TrafficStore { store.traffic }
    private var center: CLLocationCoordinate2D { .init(latitude: store.prefs.cityLat, longitude: store.prefs.cityLon) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .bottom) {
                    Text("Yol Durumu").font(.serif(25)).tracking(-0.4)
                    Spacer()
                    if traffic.busy { ProgressView().controlSize(.small) }
                    Text("Apple Haritalar · \(traffic.lastRefresh.map(Day.hm) ?? "—")").font(.mono(11, .regular)).foregroundStyle(T.ink3)
                    Button { Task { await traffic.refresh(force: true) } } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold)).foregroundStyle(T.ink2)
                    }.buttonStyle(.plain).help("Yenile").disabled(traffic.busy)
                }
                AdaptiveStack {
                    map.frame(maxWidth: .infinity).frame(height: isPhone ? 300 : 460)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Eyebrow(text: "ROTALAR")
                            Spacer()
                            presetsMenu
                        }
                        if traffic.routes.isEmpty {
                            EmptyBox(title: "Henüz rota yok", subtitle: "Aşağıdan ekle ya da hazır rotalardan seç")
                        }
                        VStack(spacing: 8) {
                            ForEach(traffic.routes) { r in
                                routeRow(r)
                                    .opacity(dragging?.id == r.id ? 0.35 : 1)
                                    .onDrag {
                                        dragging = r
                                        return NSItemProvider(object: r.id as NSString)
                                    }
                                    .onDrop(of: [.text], delegate: RouteDropDelegate(item: r, dragging: $dragging, traffic: traffic))
                            }
                        }
                        // a drop that lands between rows still ends the drag
                        .onDrop(of: [.text], isTargeted: nil) { _ in dragging = nil; return true }
                        addForm
                    }
                    .frame(width: isPhone ? nil : 360)
                }
                RelatedNews(title: "TRAFİK HABERLERİ", items: Array(store.trafficNews.prefix(8)),
                            emptyTitle: "Trafik haberi yok", emptySubtitle: "Kaza, yol kapanması ve trafik haberleri burada görünür")
            }
            .padding(isPhone ? .init(top: 4, leading: 16, bottom: 24, trailing: 16) : .init(top: 34, leading: 28, bottom: 32, trailing: 28))
        }
        .task {
            traffic.seedIfNeeded(city: store.prefs.cityName)
            position = .region(MKCoordinateRegion(center: center, span: .init(latitudeDelta: 0.3, longitudeDelta: 0.3)))
            while !Task.isCancelled {
                await traffic.refresh()
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }

    private var map: some View {
        Map(position: $position) {
            ForEach(traffic.routes) { r in
                if let s = traffic.status[r.id] {
                    MapPolyline(s.polyline)
                        .stroke(r.id == selectedID ? T.accent : s.level.color.opacity(0.75), lineWidth: r.id == selectedID ? 6 : 4)
                }
            }
            if let r = traffic.routes.first(where: { $0.id == selectedID }) {
                Marker(r.from, coordinate: r.source).tint(.gray)
                Marker(r.to, coordinate: r.destination).tint(T.accent)
            }
        }
        .mapStyle(.standard(showsTraffic: true))
        #if os(macOS)
        .mapControls { MapZoomStepper(); MapCompass() }
        #else
        .mapControls { MapCompass() }
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.rule, lineWidth: 1))
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 10) {
                ForEach([TrafficLevel.akici, .yogun, .cokYogun], id: \.label) { l in
                    HStack(spacing: 4) { Circle().fill(l.color).frame(width: 7, height: 7); Text(l.label).font(.ui(11)) }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(10)
        }
    }

    private func routeRow(_ r: TrafficRoute) -> some View {
        let s = traffic.status[r.id]
        let sel = r.id == selectedID
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: "line.3.horizontal").font(.system(size: 10, weight: .semibold)).foregroundStyle(T.ink3)
                    .help("Sürükleyerek sırala")
                Text(r.title).font(.ui(13, .semibold)).foregroundStyle(T.ink).lineLimit(1)
                Spacer()
                if let s {
                    Text("\(Int(s.minutes.rounded())) dk").font(.mono(15)).foregroundStyle(T.ink)
                } else if traffic.failed.contains(r.id) {
                    Text("hesaplanamadı").font(.mono(10.5, .regular)).foregroundStyle(T.down)
                } else {
                    ProgressView().controlSize(.mini)
                }
            }
            if let s {
                HStack(spacing: 6) {
                    Circle().fill(s.level.color).frame(width: 7, height: 7)
                    Text(s.level.label + (s.delay > 0 ? " · +\(s.delay) dk" : "")).font(.ui(11.5, .medium)).foregroundStyle(s.level.color)
                    Text("· \(String(format: "%.0f", s.distanceKm)) km · \(s.road)").font(.ui(11.5)).foregroundStyle(T.ink3).lineLimit(1)
                    if s.hasTolls {
                        Text("ÜCRETLİ").font(.mono(8.5, .semibold)).foregroundStyle(T.ink2)
                            .padding(.horizontal, 4).padding(.vertical, 2).background(T.paper3, in: RoundedRectangle(cornerRadius: 3))
                            .help("Rota ücretli otoyol ya da köprü içeriyor")
                    }
                }
            }
        }
        .padding(12)
        .background(sel ? T.accentSoft : T.paper2, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(sel ? T.accent : T.rule, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture {
            selectedID = sel ? nil : r.id
            if !sel, let s {
                let rect = s.polyline.boundingMapRect
                withAnimation { position = .rect(rect.insetBy(dx: -rect.width * 0.25, dy: -rect.height * 0.25)) }
            }
        }
        .contextMenu {
            Button("Haritalar'da aç") { TrafficStore.openInMaps(r) }
            Button("Rotayı sil", role: .destructive) { if selectedID == r.id { selectedID = nil }; traffic.remove(r) }
        }
    }

    private var presetsMenu: some View {
        Menu {
            Section("İzmir") { ForEach(RoutePresets.izmir) { p in Button(p.title) { Task { await traffic.add(p) } } } }
            Section("Manisa") { ForEach(RoutePresets.manisaList) { p in Button(p.title) { Task { await traffic.add(p) } } } }
        } label: {
            Text("Hazır rotalar ▾").font(.ui(11.5)).foregroundStyle(T.accent)
        }
        .menuStyle(.button).buttonStyle(.plain).fixedSize()
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                field("Nereden", $from)
                Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(T.ink3)
                field("Nereye", $to)
                Button {
                    adding = true; addError = nil
                    Task {
                        do { try await traffic.add(from: from.trimmingCharacters(in: .whitespaces), to: to.trimmingCharacters(in: .whitespaces), near: center); from = ""; to = "" }
                        catch { addError = error.localizedDescription }
                        adding = false
                    }
                } label: {
                    Text(adding ? "…" : "Ekle").font(.ui(12, .medium)).foregroundStyle(T.accentInk)
                        .padding(.horizontal, 10).padding(.vertical, 5).background(T.accent, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .disabled(adding || from.trimmingCharacters(in: .whitespaces).isEmpty || to.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text(addError ?? "Semt, cadde ya da yer adı yaz (örn. Bornova Metro). Sağ tık: Haritalar'da aç / sil.")
                .font(.ui(11)).foregroundStyle(addError == nil ? T.ink3 : T.down)
        }
        .padding(.top, 6)
    }

    private func field(_ placeholder: String, _ text: Binding<String>) -> some View {
        TextField(placeholder, text: text).textFieldStyle(.plain).font(.ui(12.5))
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(T.paper2, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(T.rule, lineWidth: 1))
    }
}

/// Live reordering while a route is dragged over another, as in the sidebar.
struct RouteDropDelegate: DropDelegate {
    let item: TrafficRoute
    @Binding var dragging: TrafficRoute?
    let traffic: TrafficStore

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging.id != item.id,
              let from = traffic.routes.firstIndex(where: { $0.id == dragging.id }),
              let to = traffic.routes.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            traffic.routes.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragging = nil; return true }
}

/// Bugün: the saved routes at a glance, in the order set in Yol Durumu; opens Yol Durumu.
struct TrafficGlance: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let traffic = store.traffic
        if !traffic.routes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "YOL DURUMU", link: "Harita →") { store.screen = .yol }
                Card {
                    VStack(spacing: 0) {
                        ForEach(Array(traffic.routes.prefix(4).enumerated()), id: \.element.id) { i, r in
                            if i > 0 { Rule(color: T.rule2) }
                            HStack(spacing: 8) {
                                Circle().fill(traffic.status[r.id]?.level.color ?? T.ink3.opacity(0.4)).frame(width: 7, height: 7)
                                Text(r.title).font(.ui(12.5)).lineLimit(1)
                                Spacer()
                                if let s = traffic.status[r.id] {
                                    if s.delay > 0 { Text("+\(s.delay)").font(.mono(10.5)).foregroundStyle(s.level.color) }
                                    Text("\(Int(s.minutes.rounded())) dk").font(.mono(12))
                                } else {
                                    Text("—").font(.mono(12)).foregroundStyle(T.ink3)
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 9)
                        }
                    }
                }
            }
            .task {
                while !Task.isCancelled {
                    await traffic.refresh()
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                }
            }
        }
    }
}
