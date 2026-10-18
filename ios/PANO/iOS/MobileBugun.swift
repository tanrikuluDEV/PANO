import SwiftUI

/// The sections of Bugün, in the order the user set (⚙︎ top right), each of which can be hidden.
enum BugunSection: String, CaseIterable, Identifiable {
    case piyasa, haberler, takvim, gorevler, maclar, takim, yol, not, sehrim
    var id: String { rawValue }
    var title: String {
        switch self {
        case .piyasa: "Piyasalar"
        case .haberler: "Öne çıkan haberler"
        case .takvim: "Takvim"
        case .gorevler: "Bugün yapılacaklar"
        case .maclar: "Maçlar"
        case .takim: "Takımım"
        case .yol: "Yol durumu"
        case .not: "Günün notu"
        case .sehrim: "Şehrim"
        }
    }
    var symbol: String {
        switch self {
        case .piyasa: "chart.line.uptrend.xyaxis"
        case .haberler: "newspaper"
        case .takvim: "calendar"
        case .gorevler: "checklist"
        case .maclar: "soccerball"
        case .takim: "shield.lefthalf.filled"
        case .yol: "car"
        case .not: "note.text"
        case .sehrim: "building.2"
        }
    }
}

/// Bugün on the phone: the Mac's two columns become one list of sections the user can reorder and hide.
struct MobileBugun: View {
    @Environment(AppStore.self) private var store
    @AppStorage("bugunOrder") private var orderRaw = BugunSection.allCases.map(\.rawValue).joined(separator: ",")
    @AppStorage("bugunHidden") private var hiddenRaw = ""
    @State private var editing = false

    /// Saved order, with sections added in later versions appended.
    private var order: [BugunSection] {
        let saved = orderRaw.split(separator: ",").compactMap { BugunSection(rawValue: String($0)) }
        return saved + BugunSection.allCases.filter { !saved.contains($0) }
    }
    private var hidden: Set<String> { Set(hiddenRaw.split(separator: ",").map(String.init)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                ForEach(order.filter { !hidden.contains($0.rawValue) }) { section($0) }
            }
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 24)
        }
        .refreshable { await store.refreshSlow(force: true) }
        .onAppear { AppStore.clearBadge() }
        // `-editBugun YES` (command line only): screenshot of the editor
        .onAppear { if UserDefaults.standard.bool(forKey: "editBugun") { editing = true } }
        .sheet(isPresented: $editing) {
            BugunEditor(orderRaw: $orderRaw, hiddenRaw: $hiddenRaw)
        }
    }

    @ViewBuilder private func section(_ s: BugunSection) -> some View {
        switch s {
        case .piyasa: econ
        case .haberler: FeaturedNews()
        case .takvim: TakvimCard()
        case .gorevler: TodayTodos()
        case .maclar: FootballGlance()
        case .takim: TeamCard()
        case .yol: TrafficGlance()
        case .not: DayNote()
        case .sehrim: SehrimCard()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(store.greeting).font(.serif(27)).tracking(-0.4)
                Spacer()
                Button { editing = true } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 15, weight: .semibold)).foregroundStyle(T.ink2)
                        .frame(width: 38, height: 38)
                        .background(.regularMaterial, in: Circle())
                        .overlay(Circle().stroke(T.rule, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Anasayfayı düzenle")
            }
            HStack(spacing: 8) {
                Text("\(Day.long(Date())) · \(store.prefs.cityName)").font(.ui(13)).foregroundStyle(T.ink2).lineLimit(1)
                if let w = store.weather {
                    Button { store.screen = .hava } label: { WeatherBadge(weather: w) }.buttonStyle(.plain)
                }
            }
        }
    }

    /// The Mac's row of market tiles, scrolled sideways.
    @ViewBuilder private var econ: some View {
        if store.quotes.isEmpty {
            EconStrip()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.visibleInstruments) { inst in
                        if let q = store.quotes[inst.id] {
                            Button { store.selectedIndicator = inst.id; store.screen = .ekonomi } label: {
                                EconTile(inst: inst, q: q).frame(width: 150)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .scrollClipDisabled()
        }
    }
}

/// Reorder (drag the handles) and show / hide Bugün's sections.
private struct BugunEditor: View {
    @Binding var orderRaw: String
    @Binding var hiddenRaw: String
    @Environment(\.dismiss) private var dismiss

    private var order: [BugunSection] {
        let saved = orderRaw.split(separator: ",").compactMap { BugunSection(rawValue: String($0)) }
        return saved + BugunSection.allCases.filter { !saved.contains($0) }
    }
    private var hidden: Set<String> { Set(hiddenRaw.split(separator: ",").map(String.init)) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(order) { s in
                        let off = hidden.contains(s.rawValue)
                        HStack(spacing: 12) {
                            Image(systemName: s.symbol).frame(width: 24).foregroundStyle(off ? T.ink3 : T.accent)
                            Text(s.title).foregroundStyle(off ? T.ink3 : T.ink)
                            Spacer()
                            Button { toggle(s) } label: {
                                Image(systemName: off ? "eye.slash" : "eye").foregroundStyle(off ? T.ink3 : T.accent)
                                    .frame(width: 32, height: 32).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                    .onMove { from, to in
                        var o = order
                        o.move(fromOffsets: from, toOffset: to)
                        orderRaw = o.map(\.rawValue).joined(separator: ",")
                    }
                } footer: {
                    Text("Tutamaçtan sürükleyerek sırala; göz simgesiyle bir bölümü gizle ya da göster.")
                }
                Section {
                    Button("Varsayılana dön") {
                        orderRaw = BugunSection.allCases.map(\.rawValue).joined(separator: ",")
                        hiddenRaw = ""
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Anasayfayı düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Bitti") { dismiss() } }
        }
    }

    private func toggle(_ s: BugunSection) {
        var h = hidden
        if h.contains(s.rawValue) { h.remove(s.rawValue) } else { h.insert(s.rawValue) }
        hiddenRaw = h.sorted().joined(separator: ",")
    }
}
