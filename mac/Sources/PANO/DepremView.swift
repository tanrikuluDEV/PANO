import SwiftUI
import MapKit

/// Deprem: AFAD's latest earthquakes on a map and in a list, with range / magnitude / nearby filters and the
/// alert settings. The list and map share the selection; picking a row flies the map to it.
struct DepremView: View {
    @Environment(AppStore.self) private var store
    @State private var range = 24
    @State private var minMag = 0.0
    @State private var nearby = false
    @State private var camera: MapCameraPosition = .region(DepremView.turkey)

    static let turkey = MKCoordinateRegion(center: .init(latitude: 39.0, longitude: 35.3), span: .init(latitudeDelta: 11, longitudeDelta: 22))
    private var quakes: QuakeStore { store.quakes }
    private var cityLat: Double { store.prefs.cityLat }
    private var cityLon: Double { store.prefs.cityLon }

    private var list: [Quake] {
        (range == 24 ? quakes.day : quakes.week).filter { q in
            q.magnitude >= minMag && (!nearby || q.distance(toLat: cityLat, lon: cityLon) <= 300)
        }
    }

    var body: some View {
        let list = list
        VStack(spacing: 0) {
            header(list)
            HStack(spacing: 0) {
                map(list).frame(maxWidth: .infinity, maxHeight: .infinity)
                listColumn(list).frame(width: 360).overlay(alignment: .leading) { VRule() }
            }
        }
        .task(id: range) { if range > 24 { await quakes.loadWeek() } }
        .task { if quakes.day.isEmpty { await store.refreshQuakes() } }
        .onChange(of: quakes.selectedID) { _, id in
            guard let q = list.first(where: { $0.id == id }) else { return }
            withAnimation(.easeInOut(duration: 0.6)) {
                camera = .region(MKCoordinateRegion(center: q.coordinate, span: .init(latitudeDelta: 2.2, longitudeDelta: 3)))
            }
        }
        .onChange(of: nearby) { _, on in
            withAnimation(.easeInOut(duration: 0.6)) {
                camera = .region(on ? MKCoordinateRegion(center: .init(latitude: cityLat, longitude: cityLon), span: .init(latitudeDelta: 6, longitudeDelta: 8))
                                    : Self.turkey)
            }
        }
    }

    // MARK: Header

    private func header(_ list: [Quake]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("Deprem").font(.serif(25)).tracking(-0.4)
                Spacer()
                Text("\(list.count) deprem · AFAD" + (quakes.lastUpdate.map { " · \(Day.hm($0))" } ?? ""))
                    .font(.mono(11, .regular)).foregroundStyle(T.ink3)
            }
            HStack(spacing: 8) {
                Segmented(items: [(24, "Son 24 saat"), (168, "Son 7 gün")], selection: $range, mono: false, radius: 7, hPad: 10)
                Segmented(items: [(0.0, "Tümü"), (2.0, "2+"), (3.0, "3+"), (4.0, "4+")], selection: $minMag, mono: true, radius: 7, hPad: 9)
                Button { nearby.toggle() } label: {
                    Pill(text: "Yakınımdakiler · \(store.prefs.cityName)", selected: nearby)
                }.buttonStyle(.plain).help("\(store.prefs.cityName) çevresinde 300 km")
                Spacer(minLength: 8)
                alertMenu
            }
        }
        .padding(.init(top: 34, leading: 24, bottom: 14, trailing: 24))
        .overlay(alignment: .bottom) { Rule() }
    }

    private var alertMenu: some View {
        let p = store.prefs
        return Menu {
            Toggle("Deprem bildirimi", isOn: Binding(get: { store.prefs.quakeNotify }, set: { store.prefs.quakeNotify = $0 }))
            Divider()
            Section("En az büyüklük") {
                ForEach([3.0, 3.5, 4.0, 4.5, 5.0], id: \.self) { m in
                    Button { store.prefs.quakeMinMag = m } label: {
                        Text((p.quakeMinMag == m ? "✓ " : "   ") + String(format: "%.1f", m).replacingOccurrences(of: ".", with: ",") + "+")
                    }
                }
            }
            Section("\(p.cityName) şehrine uzaklık") {
                ForEach([(100, "100 km"), (300, "300 km"), (500, "500 km"), (0, "Tüm Türkiye")], id: \.0) { r, label in
                    Button { store.prefs.quakeRadius = r } label: { Text((p.quakeRadius == r ? "✓ " : "   ") + label) }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: p.quakeNotify ? "bell.fill" : "bell.slash").font(.system(size: 11))
                Text(p.quakeNotify ? "\(String(format: "%.1f", p.quakeMinMag).replacingOccurrences(of: ".", with: ","))+ · \(p.quakeRadius == 0 ? "Türkiye" : "\(p.quakeRadius) km")" : "Bildirim kapalı")
                    .font(.ui(12, .medium))
            }
            .foregroundStyle(p.quakeNotify ? T.accent : T.ink3)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(p.quakeNotify ? T.accentSoft : T.paper2, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(p.quakeNotify ? T.accent.opacity(0.4) : T.rule, lineWidth: 1))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("Deprem bildirim ayarları")
    }

    // MARK: Map

    private func map(_ list: [Quake]) -> some View {
        Map(position: $camera, selection: Binding(get: { quakes.selectedID }, set: { quakes.selectedID = $0 })) {
            Annotation(store.prefs.cityName, coordinate: .init(latitude: cityLat, longitude: cityLon)) {
                Image(systemName: "house.fill").font(.system(size: 10)).foregroundStyle(.white)
                    .padding(5).background(T.accent, in: Circle())
            }
            // smallest first, so big events draw on top
            ForEach(list.sorted { $0.magnitude < $1.magnitude }) { q in
                Annotation("", coordinate: q.coordinate, anchor: .center) {
                    QuakeDot(quake: q, selected: q.id == quakes.selectedID)
                }
                .tag(q.id)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .overlay(alignment: .bottomLeading) { legend.padding(12) }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach([(1.5, "<3"), (3.2, "3–4"), (4.2, "4–5"), (5.2, "5+")], id: \.1) { m, label in
                HStack(spacing: 4) { Circle().fill(QuakeDot.color(m)).frame(width: 8, height: 8); Text(label).font(.mono(9.5)) }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }

    // MARK: List

    @ViewBuilder private func listColumn(_ list: [Quake]) -> some View {
        let loading = range == 24 ? quakes.state : quakes.weekState
        if case .failed(let m) = loading, list.isEmpty {
            ErrorCard(eyebrow: "HATA · DEPREM", message: m) { Task { range == 24 ? await store.refreshQuakes() : await quakes.loadWeek() } }
                .padding(16).frame(maxHeight: .infinity, alignment: .top)
        } else if list.isEmpty && loading == .loading {
            SkeletonCard(title: "YÜKLENİYOR · DEPREMLER").padding(16).frame(maxHeight: .infinity, alignment: .top)
        } else if list.isEmpty {
            EmptyBox(title: "Bu filtreyle deprem yok", subtitle: "Büyüklük ya da zaman aralığını değiştir").padding(16)
                .frame(maxHeight: .infinity, alignment: .top)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(list) { q in QuakeRow(quake: q, cityLat: cityLat, cityLon: cityLon).id(q.id) }
                    }
                }
                .onChange(of: quakes.selectedID) { _, id in if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } } }
            }
        }
    }
}

struct QuakeDot: View {
    let quake: Quake
    var selected = false
    static func color(_ m: Double) -> Color {
        m >= 5 ? Color(nsColor: oklch(0.55, 0.20, 25)) : m >= 4 ? Color(nsColor: oklch(0.68, 0.17, 50))
            : m >= 3 ? Color(nsColor: oklch(0.80, 0.15, 90)) : Color(nsColor: oklch(0.62, 0.05, 240))
    }
    var body: some View {
        let size = max(8, min(46, 5 * pow(1.55, quake.magnitude)))
        let recent = Date().timeIntervalSince(quake.date) < 3600
        Circle()
            .fill(Self.color(quake.magnitude).opacity(0.75))
            .overlay(Circle().stroke(.white.opacity(selected ? 1 : 0.8), lineWidth: selected ? 2.5 : 1))
            .frame(width: size, height: size)
            .overlay { if recent { PulseRing(color: Self.color(quake.magnitude)).frame(width: size * 2, height: size * 2) } }
            .shadow(color: .black.opacity(0.25), radius: 2)
            .scaleEffect(selected ? 1.25 : 1)
            .animation(.spring(response: 0.3), value: selected)
    }
}

/// Expanding ring for events in the last hour.
private struct PulseRing: View {
    let color: Color
    @State private var on = false
    var body: some View {
        Circle().stroke(color, lineWidth: 2)
            .scaleEffect(on ? 1 : 0.4).opacity(on ? 0 : 0.8)
            .onAppear { withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { on = true } }
            .allowsHitTesting(false)
    }
}

private struct QuakeRow: View {
    @Environment(AppStore.self) private var store
    let quake: Quake
    let cityLat: Double, cityLon: Double
    @State private var hover = false
    var body: some View {
        let sel = store.quakes.selectedID == quake.id
        Button { store.quakes.selectedID = quake.id } label: {
            HStack(spacing: 12) {
                Text(quake.magText).font(.mono(15, .bold)).foregroundStyle(quake.magnitude >= 3 ? .black.opacity(0.8) : .white)
                    .frame(width: 46, height: 36)
                    .background(QuakeDot.color(quake.magnitude), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(quake.location).font(.ui(13, sel ? .semibold : .regular)).foregroundStyle(T.ink).lineLimit(1)
                    Text("\(ago(quake.date)) · \(Day.hm(quake.date)) · \(Int(quake.depth.rounded())) km derinlik")
                        .font(.mono(9.5, .regular)).foregroundStyle(T.ink3).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text("\(Int(quake.distance(toLat: cityLat, lon: cityLon).rounded())) km").font(.mono(10, .regular)).foregroundStyle(T.ink3)
                    .help("\(store.prefs.cityName) şehrine uzaklık")
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(sel ? T.accentSoft : hover ? T.paper3 : .clear)
            .overlay(alignment: .leading) { Rectangle().fill(sel ? T.accent : .clear).frame(width: 2) }
            .overlay(alignment: .bottom) { Rule(color: T.rule2) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private func ago(_ d: Date) -> String {
        let m = Int(Date().timeIntervalSince(d) / 60)
        if m < 1 { return "az önce" }
        if m < 60 { return "\(m) dk önce" }
        if m < 24 * 60 { return "\(m / 60) sa önce" }
        return Day.format(d, "d MMM")
    }
}
