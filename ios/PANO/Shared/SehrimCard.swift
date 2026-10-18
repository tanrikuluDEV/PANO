import SwiftUI
#if os(macOS)
#if os(macOS)
import AppKit
#endif
#endif

/// Per-province links bundled with the app (Resources/city-links.json, made by scripts/make_city_links.py).
struct CityLinks: Decodable {
    let eczane: String?          // eczaneler.gen.tr slug, e.g. "manisa"
    let districts: [String]      // district slugs under it, e.g. "salihli"
    let water: String?
    let power: String?
    let belediye: String?

    static let all: [String: CityLinks] = {
        guard let u = Bundle.main.url(forResource: "city-links", withExtension: "json"),
              let d = try? JSONDecoder().decode([String: CityLinks].self, from: Data(contentsOf: u)) else { return [:] }
        return d
    }()
}

/// Bugün › Şehrim: duty pharmacies, everyday city services and emergency numbers for the weather city.
/// Every link opens in the in-app browser, so the pages load as an ordinary visit.
struct SehrimCard: View {
    @Environment(AppStore.self) private var store
    @State private var copied: String?
    /// Bumped when a district is picked, so the card re-reads the saved choice.
    @State private var pickVersion = 0

    private static let emergency: [(String, String)] = [("112", "Acil"), ("122", "AFAD"), ("185", "Su arıza"),
                                                         ("186", "Elektrik arıza"), ("187", "Doğalgaz"), ("184", "SABİM")]

    var body: some View {
        if let province = Provinces.match(store.prefs.cityName), let links = CityLinks.all[province] {
            let _ = pickVersion
            let district = district(province, links)
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "ŞEHRİM · \(province.uppercased(with: Locale(identifier: "tr_TR")))")
                Card {
                    VStack(alignment: .leading, spacing: 0) {
                        if let slug = links.eczane { pharmacyRow(province, slug: slug, links: links, district: district) }
                        Rule(color: T.rule2)
                        shortcuts(links).padding(12)
                        Rule(color: T.rule2)
                        emergencyRow.padding(12)
                    }
                }
            }
        }
    }

    // MARK: Pharmacy

    /// The picked district, else the weather city itself when it's a district ("Salihli"), else the whole province.
    private func district(_ province: String, _ links: CityLinks) -> String? {
        let key = "eczaneDistrict|" + province
        if let saved = UserDefaults.standard.string(forKey: key) { return saved.isEmpty ? nil : saved }
        let own = Provinces.fold(store.prefs.cityName).replacingOccurrences(of: " ", with: "-")
        return links.districts.contains(own) ? own : nil
    }

    private func pharmacyRow(_ province: String, slug: String, links: CityLinks, district: String?) -> some View {
        let url = URL(string: "https://www.eczaneler.gen.tr/nobetci-" + slug + (district.map { "-" + $0 } ?? ""))!
        return HStack(spacing: 12) {
            Button { store.openWeb(url) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "cross.case.fill").font(.system(size: 15)).foregroundStyle(T.down)
                        .frame(width: 34, height: 34).background(T.downSoft, in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nöbetçi eczaneler").font(.ui(13.5, .semibold)).foregroundStyle(T.ink)
                        Text("\(district.map(districtName) ?? "\(province) geneli") · bugün").font(.mono(10, .regular)).foregroundStyle(T.ink3)
                    }
                    Spacer(minLength: 4)
                    Text("↗").font(.ui(13)).foregroundStyle(T.accent)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if !links.districts.isEmpty {
                Menu {
                    Button("\(province) geneli") { UserDefaults.standard.set("", forKey: "eczaneDistrict|" + province); pickVersion += 1 }
                    Divider()
                    ForEach(links.districts, id: \.self) { d in
                        Button(districtName(d)) { UserDefaults.standard.set(d, forKey: "eczaneDistrict|" + province); pickVersion += 1 }
                    }
                } label: {
                    Text("İlçe ▾").font(.ui(11.5)).foregroundStyle(T.ink2)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(T.paper3, in: RoundedRectangle(cornerRadius: 6))
                }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().help("İlçe seç")
            }
        }
        .padding(12)
    }

    /// "sehzadeler" → "Şehzadeler": the site's slugs have no Turkish letters, so restore the common ones.
    private func districtName(_ slug: String) -> String {
        let known = ["sehzadeler": "Şehzadeler", "alasehir": "Alaşehir", "gordes": "Gördes", "kirkagac": "Kırkağaç", "koprubasi": "Köprübaşı",
                     "sarigol": "Sarıgöl", "saruhanli": "Saruhanlı", "golmarmara": "Gölmarmara", "odemis": "Ödemiş", "cesme": "Çeşme",
                     "karsiyaka": "Karşıyaka", "bayrakli": "Bayraklı", "cigli": "Çiğli", "kadikoy": "Kadıköy", "uskudar": "Üsküdar",
                     "besiktas": "Beşiktaş", "sisli": "Şişli", "bakirkoy": "Bakırköy", "cankaya": "Çankaya", "kecioren": "Keçiören"]
        if let k = known[slug] { return k }
        return slug.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    // MARK: Shortcuts

    private func shortcuts(_ links: CityLinks) -> some View {
        var items: [(String, String, URL?)] = [
            ("cross.circle", "MHRS", URL(string: "https://www.mhrs.gov.tr")),
            ("person.text.rectangle", "e-Devlet", URL(string: "https://www.turkiye.gov.tr")),
        ]
        if let b = links.belediye { items.append(("building.columns", "Belediye", URL(string: b))) }
        items.append(("bolt.slash", "Elektrik kesintileri", URL(string: links.power ?? "https://elektrikkesintiler.com.tr")))
        items.append(("drop.degreesign.slash", "Su kesintileri", URL(string: links.water ?? "https://sukesintisi.com.tr")))
        return FlowChips(items: items.map { ShortcutItem(symbol: $0.0, title: $0.1, url: $0.2) }) { item in
            Button { if let u = item.url { store.openWeb(u) } } label: {
                HStack(spacing: 5) {
                    Image(systemName: item.symbol).font(.system(size: 10.5))
                    Text(item.title).font(.ui(12))
                }
                .foregroundStyle(T.ink)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(T.paper2, in: Capsule()).overlay(Capsule().stroke(T.rule, lineWidth: 1))
                .contentShape(Capsule())
            }.buttonStyle(.plain)
        }
    }

    private struct ShortcutItem: Identifiable { let symbol, title: String; let url: URL?; var id: String { title } }

    // MARK: Emergency numbers

    private var emergencyRow: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(copied.map { "\($0) kopyalandı ✓" } ?? "ACİL NUMARALAR · tıkla, kopyala")
                .font(.mono(9, .medium)).tracking(0.6).foregroundStyle(copied == nil ? T.ink3 : T.up)
            FlowChips(items: Self.emergency.map { EmergencyItem(number: $0.0, label: $0.1) }) { e in
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(e.number, forType: .string)
                    withAnimation(.easeOut(duration: 0.15)) { copied = e.number }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { if copied == e.number { withAnimation { copied = nil } } }
                } label: {
                    HStack(spacing: 5) {
                        Text(e.number).font(.mono(12, .bold)).foregroundStyle(e.number == "112" ? T.down : T.ink)
                        Text(e.label).font(.ui(11)).foregroundStyle(T.ink2)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(copied == e.number ? T.upSoft : T.paper3, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain).help("\(e.number) numarasını kopyala")
            }
        }
    }

    private struct EmergencyItem: Identifiable { let number, label: String; var id: String { number } }
}
