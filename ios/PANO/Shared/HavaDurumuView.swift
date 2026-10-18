import SwiftUI

struct HavaDurumuView: View {
    @Environment(AppStore.self) private var store
    @State private var cityQuery = ""
    @State private var cityResults: [City] = []
    @State private var searching = false

    var body: some View {
        Group {
            if let d = store.weatherDetail {
                content(d)
            } else if case .failed(let m) = store.weatherDetailState {
                VStack(alignment: .leading, spacing: 20) {
                    header(nil)
                    ErrorCard(eyebrow: "HATA · HAVA DURUMU", message: m) { Task { await store.refreshWeather() } }.frame(maxWidth: 340)
                }.padding(.init(top: 34, leading: 28, bottom: 32, trailing: 28)).frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    header(nil)
                    SkeletonCard(title: "YÜKLENİYOR · HAVA DURUMU", widths: [0.9, 0.7, 0.85, 0.6])
                }.padding(.init(top: 34, leading: 28, bottom: 32, trailing: 28))
            }
        }
        .task { await store.refreshWeather() }
        .task(id: cityQuery) {
            let q = cityQuery.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2 else { cityResults = []; return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            let r = await CityService.search(q)
            if !Task.isCancelled { cityResults = r }
        }
    }

    private func header(_ d: WeatherDetail?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hava Durumu").font(.serif(25)).tracking(-0.4)
                    Text("\(store.prefs.cityName) · \(Day.long(Date()))").font(.ui(13)).foregroundStyle(T.ink2)
                }
                Spacer()
                Text("Kaynak · Open-Meteo · \(store.lastSync.map(Day.hm) ?? "—")").font(.mono(11, .regular)).foregroundStyle(T.ink3)
            }
            citySearchField
            if !cityQuery.trimmingCharacters(in: .whitespaces).isEmpty { citySearchResults }
        }
    }

    private var citySearchField: some View {
        HStack(spacing: 6) {
            Text("⌕").font(.ui(13)).foregroundStyle(T.ink3)
            TextField("Başka şehir ara (ör. Eskişehir, Berlin)", text: $cityQuery).textFieldStyle(.plain).font(.ui(12.5)).frame(width: 240)
            if !cityQuery.isEmpty {
                Button { cityQuery = ""; cityResults = [] } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(T.ink3)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(T.paper2, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(T.rule, lineWidth: 1))
        .fixedSize()
    }

    private var citySearchResults: some View {
        Card {
            VStack(spacing: 0) {
                if cityResults.isEmpty {
                    Text("Sonuç yok").font(.ui(12.5)).foregroundStyle(T.ink3).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(cityResults.prefix(6).enumerated()), id: \.element.id) { i, c in
                        Button { pick(c) } label: {
                            HStack(spacing: 8) {
                                Text(c.name).font(.ui(13))
                                Text(c.subtitle).font(.ui(11.5)).foregroundStyle(T.ink3).lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 13).padding(.vertical, 9).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .overlay(alignment: .top) { if i > 0 { Rule(color: T.rule2) } }
                    }
                }
            }
        }.frame(maxWidth: 340)
    }

    private func pick(_ c: City) {
        store.setCity(c)
        cityQuery = ""; cityResults = []
    }

    private func content(_ d: WeatherDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header(d)
                currentCard(d)
                hourlyCard(d)
                dailyCard(d)
                RelatedNews(title: "HAVA HABERLERİ", items: store.weatherNews,
                            emptyTitle: "Hava durumu haberi yok", emptySubtitle: "Ayarlar'dan haber kaynağı etkinleştir") {
                    store.newsQuery = "hava durumu"; store.newsSourceFilter = nil; store.screen = .haberler
                }
            }
            .padding(.init(top: 34, leading: 28, bottom: 32, trailing: 28))
        }
    }

    // MARK: Current conditions

    private func currentCard(_ d: WeatherDetail) -> some View {
        let sm = d.current.summary
        return Card(padding: 22) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 24) {
                    Image(systemName: sm.symbol).symbolRenderingMode(.multicolor).font(.system(size: 52))
                        .frame(width: 76, height: 76)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(d.current.tempText).font(.mono(46)).tracking(-1)
                            Text(sm.text).font(.serif(19)).foregroundStyle(T.ink2)
                        }
                        Text("Hissedilen \(Int(d.feelsLike.rounded()))°").font(.ui(13)).foregroundStyle(T.ink3)
                    }
                    Spacer()
                }
                HStack(spacing: 0) {
                    detail("humidity", "Nem", "%\(d.humidity)")
                    detail("wind", "Rüzgâr", "\(Int(d.current.wind.rounded())) km/sa \(d.windCompass)")
                    detail("gauge.with.dots.needle.33percent", "Basınç", "\(Int(d.pressure.rounded())) hPa")
                    detail("sun.max", "UV endeksi", "\(String(format: "%.1f", d.uvIndex)) · \(d.uvLabel)")
                }
                if let today = d.daily.first {
                    HStack(spacing: 0) {
                        detail("sunrise.fill", "Gün doğumu", Day.hm(today.sunrise))
                        detail("sunset.fill", "Gün batımı", Day.hm(today.sunset))
                        detail("thermometer.high", "Bugün en yüksek", "\(Int(today.tempMax.rounded()))°")
                        detail("thermometer.low", "Bugün en düşük", "\(Int(today.tempMin.rounded()))°")
                    }
                }
            }
        }
    }

    private func detail(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(T.accent).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.mono(9.5)).tracking(0.4).foregroundStyle(T.ink3)
                Text(value).font(.ui(13, .medium))
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Hourly

    private func hourlyCard(_ d: WeatherDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "SAATLİK")
            Card(padding: 16) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 22) {
                        ForEach(d.hourly.prefix(24)) { h in
                            let sm = h.summary
                            VStack(spacing: 7) {
                                Text(isNow(h.time) ? "Şimdi" : Day.format(h.time, "HH:mm")).font(.mono(10.5)).foregroundStyle(T.ink3)
                                Image(systemName: sm.symbol).symbolRenderingMode(.multicolor).font(.system(size: 18)).frame(height: 20)
                                Text("\(Int(h.temp.rounded()))°").font(.mono(13, .medium))
                                if h.precipChance >= 20 {
                                    HStack(spacing: 2) {
                                        Image(systemName: "drop.fill").font(.system(size: 8)).foregroundStyle(T.accent)
                                        Text("\(h.precipChance)%").font(.mono(9, .regular)).foregroundStyle(T.accent)
                                    }
                                } else {
                                    Color.clear.frame(height: 11)
                                }
                            }
                        }
                    }.padding(.vertical, 2)
                }
            }
        }
    }

    private func isNow(_ t: Date) -> Bool { abs(t.timeIntervalSinceNow) < 3600 && Day.cal.component(.hour, from: t) == Day.cal.component(.hour, from: Date()) }

    // MARK: 7-day outlook

    private func dailyCard(_ d: WeatherDetail) -> some View {
        let maxT = d.daily.map(\.tempMax).max() ?? 1, minT = d.daily.map(\.tempMin).min() ?? 0
        let span = max(maxT - minT, 1)
        return VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "7 GÜNLÜK")
            Card {
                VStack(spacing: 0) {
                    ForEach(Array(d.daily.enumerated()), id: \.element.id) { i, day in
                        let sm = day.summary
                        HStack(spacing: 14) {
                            Text(i == 0 ? "Bugün" : Day.format(day.date, "EEEE")).font(.ui(13, i == 0 ? .semibold : .regular))
                                .frame(width: 84, alignment: .leading)
                            Image(systemName: sm.symbol).symbolRenderingMode(.multicolor).font(.system(size: 15)).frame(width: 22)
                            HStack(spacing: 3) {
                                Image(systemName: "drop.fill").font(.system(size: 8)).foregroundStyle(T.accent)
                                Text("\(day.precipChance)%").font(.mono(10, .regular)).foregroundStyle(T.ink3)
                            }.frame(width: 40, alignment: .leading).opacity(day.precipChance >= 10 ? 1 : 0)
                            Text("\(Int(day.tempMin.rounded()))°").font(.mono(12, .regular)).foregroundStyle(T.ink3).frame(width: 26, alignment: .trailing)
                            GeometryReader { geo in
                                let lo = CGFloat((day.tempMin - minT) / span), hi = CGFloat((day.tempMax - minT) / span)
                                ZStack(alignment: .leading) {
                                    Capsule().fill(T.paper3).frame(height: 4)
                                    Capsule().fill(LinearGradient(colors: [T.up, T.down.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: max(geo.size.width * (hi - lo), 4), height: 4)
                                        .offset(x: geo.size.width * lo)
                                }
                            }.frame(height: 4)
                            Text("\(Int(day.tempMax.rounded()))°").font(.mono(12, .medium)).frame(width: 26, alignment: .trailing)
                        }
                        .padding(.horizontal, 15).padding(.vertical, 11)
                        .overlay(alignment: .top) { if i > 0 { Rule(color: T.rule2) } }
                    }
                }
            }
        }
    }
}
