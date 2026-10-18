import SwiftUI

struct EkonomiView: View {
    @Environment(AppStore.self) private var store
    @State private var amount = "250"
    @AppStorage("convFrom") private var convFrom = "USD"
    @AppStorage("convTo") private var convTo = "TRY"

    private var active: Instrument { allInstruments.first { $0.id == store.selectedIndicator } ?? allInstruments[0] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .bottom) {
                    Text("Ekonomi").font(.serif(25)).tracking(-0.4)
                    Spacer()
                    Text("Kaynak · Yahoo Finance · \(store.lastSync.map(Day.hm) ?? "—")").font(.mono(11, .regular)).foregroundStyle(T.ink3)
                }
                if store.quotes.isEmpty {
                    if case .failed(let m) = store.econState {
                        ErrorCard(eyebrow: "HATA · EKONOMİ", message: m) { Task { await store.refreshEconomy() } }.frame(maxWidth: 340)
                    } else { SkeletonCard(title: "YÜKLENİYOR · EKONOMİ").frame(maxWidth: 340) }
                } else {
                    HStack(spacing: 10) {
                        ForEach(store.visibleInstruments) { inst in
                            if let q = store.quotes[inst.id] {
                                let sel = inst.id == store.selectedIndicator
                                Button { store.selectedIndicator = inst.id; Task { await store.loadRange() } } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(inst.code).font(.mono(9.5)).tracking(0.8).foregroundStyle(T.ink3).lineLimit(1)
                                        Text(inst.priceText(q)).font(.mono(18)).tracking(-0.4).lineLimit(1).minimumScaleFactor(0.6)
                                        Text(q.changeText).font(.mono(11)).foregroundStyle(q.color)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                    .background(sel ? T.accentSoft : T.paper2, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(sel ? T.accent : T.rule, lineWidth: 1))
                                    .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    HStack(alignment: .top, spacing: 20) {
                        chartCard.frame(maxWidth: .infinity)
                        VStack(spacing: 14) { converter; dayRange }.frame(width: 296)
                    }
                    FuelCard()
                    RelatedNews(title: "EKONOMİ HABERLERİ", items: store.ekonomiNews,
                                emptyTitle: "Ekonomi haberi yok", emptySubtitle: "Ayarlar'dan haber kaynağı etkinleştir") {
                        store.newsQuery = ""; store.newsSourceFilter = nil; store.newsCategory = "Ekonomi"; store.screen = .haberler
                    }
                }
            }
            .padding(.init(top: 34, leading: 28, bottom: 32, trailing: 28))
        }
    }

    private var chartCard: some View {
        let inst = active
        let q = store.activeQuote ?? store.quotes[inst.id]
        return Card(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(inst.name).font(.ui(13)).foregroundStyle(T.ink2)
                        if let q {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(inst.priceText(q) + (inst.unit.isEmpty ? "" : " " + inst.unit)).font(.mono(34)).tracking(-1)
                                Text(q.changeText).font(.mono(13)).foregroundStyle(q.color)
                            }
                        }
                    }
                    Spacer()
                    Segmented(items: ChartRange.allCases.map { ($0, $0.rawValue) }, selection: Binding(get: { store.range }, set: { store.range = $0; Task { await store.loadRange() } }), mono: true, radius: 7, hPad: 11)
                }
                if let q, q.points.count > 1 {
                    AreaChart(points: q.points, decimals: inst.decimals, unit: inst.unit, range: store.range).frame(height: 230)
                    HStack {
                        ForEach(Array(axisLabels(q).enumerated()), id: \.offset) { i, l in
                            if i > 0 { Spacer() }
                            Text(l).font(.mono(10, .regular)).foregroundStyle(T.ink3)
                        }
                    }
                } else {
                    Striped(label: "grafik yükleniyor", labelSize: 10, spacing: 9).frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private func axisLabels(_ q: Quote) -> [String] {
        let pts = q.points
        guard pts.count > 3 else { return [] }
        return [0, pts.count / 3, 2 * pts.count / 3, pts.count - 1].map { Day.format(pts[$0].t, store.range.axisFormat) }
    }

    private var converter: some View {
        let v = Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0
        let result = store.convert(v, from: convFrom, to: convTo)
        let unit = store.convert(1, from: convFrom, to: convTo)
        return Card(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "PARA ÇEVİRİCİ")
                VStack(spacing: 6) {
                    HStack {
                        TextField("0", text: $amount).textFieldStyle(.plain).font(.mono(16))
                        currencyMenu($convFrom)
                    }
                    .padding(.horizontal, 11).padding(.vertical, 9).background(T.paper, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(T.rule, lineWidth: 1))
                    Button { swap(&convFrom, &convTo) } label: {
                        Image(systemName: "arrow.up.arrow.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(T.ink2)
                            .frame(width: 28, height: 22).background(T.paper3, in: Capsule()).contentShape(Rectangle())
                    }.buttonStyle(.plain).help("Para birimlerini yer değiştir")
                    HStack {
                        Text(result.map { format($0, decimals: digits(for: $0)) } ?? "—").font(.mono(16)).lineLimit(1).minimumScaleFactor(0.6)
                        Spacer()
                        currencyMenu($convTo)
                    }
                    .padding(.horizontal, 11).padding(.vertical, 9).background(T.paper3, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(T.rule2, lineWidth: 1))
                }
                Text(unit.map { "1 \(label(convFrom)) = \(format($0, decimals: digits(for: $0, rate: true))) \(label(convTo)) · \(source)" } ?? "Kur alınamadı")
                    .font(.mono(10, .regular)).foregroundStyle(T.ink3).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func currencyMenu(_ sel: Binding<String>) -> some View {
        Menu {
            ForEach(allCurrencies) { c in
                Button { sel.wrappedValue = c.code } label: {
                    Text("\(label(c.code)) · \(c.name)")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(label(sel.wrappedValue)).font(.mono(12)).foregroundStyle(T.ink2)
                Text("▾").font(.system(size: 8)).foregroundStyle(T.ink3)
            }.contentShape(Rectangle())
        }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }

    private func label(_ code: String) -> String { code == "GRAM" ? "gr altın" : code }
    private func digits(for v: Double, rate: Bool = false) -> Int {
        let a = abs(v)
        return a >= 1000 ? 2 : a >= 1 ? (rate ? 4 : 2) : a >= 0.01 ? 4 : 6
    }
    /// Live market quotes for TRY / EUR / gold, the daily table for everything else.
    private var source: String {
        let live: Set<String> = ["TRY", "EUR", "GRAM", "USD"]
        return live.isSuperset(of: [convFrom, convTo]) ? "canlı piyasa" : "günlük kur"
    }

    private var dayRange: some View {
        let inst = active
        let q = store.quotes[inst.id]
        return Card(padding: 16) {
            VStack(alignment: .leading, spacing: 11) {
                Eyebrow(text: "GÜN ARALIĞI")
                ForEach([("En düşük", q?.low), ("En yüksek", q?.high), ("Önceki kapanış", q?.prev)], id: \.0) { name, v in
                    HStack {
                        Text(name).font(.ui(12.5)).foregroundStyle(T.ink2); Spacer()
                        Text(v.map { format($0, decimals: inst.decimals) } ?? "—").font(.mono(12.5))
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Ekonomi › Akaryakıt: pump prices in one province, each with its latest change.
struct FuelCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let fuel = store.fuel
        let row = fuel.selected(weatherCity: store.prefs.cityName)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Eyebrow(text: "AKARYAKIT")
                if row != nil { cityMenu(row) }
                Spacer()
                Text("Petrol Ofisi · KDV dahil · \(fuel.lastFetch.map { Day.format($0, "d MMM HH:mm") } ?? "—")")
                    .font(.mono(10, .regular)).foregroundStyle(T.ink3)
            }
            if let row {
                HStack(spacing: 10) {
                    ForEach(FuelKind.allCases, id: \.self) { k in tile(k, row) }
                }
            } else if case .failed(let m) = fuel.state {
                ErrorCard(eyebrow: "HATA · AKARYAKIT", message: m) { Task { await store.refreshFuel(force: true) } }.frame(maxWidth: 340)
            } else {
                SkeletonCard(title: "YÜKLENİYOR · AKARYAKIT").frame(maxWidth: 340)
            }
        }
        .task { await store.refreshFuel() }
    }

    private func tile(_ k: FuelKind, _ row: FuelPrice) -> some View {
        let change = store.fuel.lastChange(k, id: row.id)
        return Card(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(k.rawValue.uppercased(with: Locale(identifier: "tr_TR"))).font(.mono(9.5)).tracking(0.8).foregroundStyle(T.ink3)
                    Text(k.detail).font(.mono(9.5, .regular)).foregroundStyle(T.ink3.opacity(0.8))
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(k.value(row).map(Fuel.tl) ?? "—").font(.mono(24)).tracking(-0.6)
                    Text("TL/L").font(.mono(10, .regular)).foregroundStyle(T.ink3)
                }
                if let change {
                    Text("\(change.delta > 0 ? "↑" : "↓") \(Fuel.tl(abs(change.delta))) TL · \(Day.format(change.date, "d MMMM"))")
                        .font(.mono(10.5)).foregroundStyle(change.delta > 0 ? T.down : T.up)
                } else {
                    Text("Son değişiklik henüz görülmedi").font(.mono(10, .regular)).foregroundStyle(T.ink3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func cityMenu(_ row: FuelPrice?) -> some View {
        let tr = Locale(identifier: "tr_TR")
        let rows = store.fuel.prices.sorted { $0.name.compare($1.name, locale: tr) == .orderedAscending }
        return Menu {
            Button("Hava durumu şehri (\(Provinces.match(store.prefs.cityName) ?? store.prefs.cityName))") { store.fuel.pickedID = nil }
            Divider()
            ForEach(rows) { r in Button(r.name) { store.fuel.pickedID = r.id } }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "mappin.and.ellipse").font(.system(size: 10.5))
                Text("\(row?.name ?? "İl seç") ▾").font(.ui(12, .medium))
            }
            .foregroundStyle(T.accent)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(T.accentSoft, in: RoundedRectangle(cornerRadius: 7))
        }
        .menuStyle(.button).buttonStyle(.plain).fixedSize()
    }
}
