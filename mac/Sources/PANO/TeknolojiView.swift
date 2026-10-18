import SwiftUI

/// Dedicated Technology tab: Türkçe teknoloji dünyası haberleri — the same two-pane reading
/// experience as Haberler, scoped to the "Teknoloji" category so it never needs a category picker.
struct TeknolojiView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Teknoloji").font(.serif(25)).tracking(-0.4)
                    Spacer()
                    Text(store.teknolojiQuery.trimmingCharacters(in: .whitespaces).isEmpty
                         ? "\(store.filteredTeknoloji.count) başlık · \(store.teknolojiSources.count) kaynak"
                         : "\(store.filteredTeknoloji.count) sonuç").font(.mono(11, .regular)).foregroundStyle(T.ink3)
                }
                HStack(spacing: 8) {
                    Menu {
                        Button("Tümü") { store.teknolojiSourceFilter = nil }
                        Divider()
                        ForEach(store.teknolojiSources) { s in Button(s.name) { store.teknolojiSourceFilter = s.id } }
                    } label: {
                        Text("Kaynak: \(allNewsSources.first { $0.id == store.teknolojiSourceFilter }?.name ?? "Tümü") ▾")
                            .font(.ui(12)).foregroundStyle(T.ink2)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(T.paper2, in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(T.rule, lineWidth: 1))
                    }.menuStyle(.button).buttonStyle(.plain).fixedSize()
                    Spacer(minLength: 8)
                    HStack(spacing: 6) {
                        Text("⌕").font(.ui(13)).foregroundStyle(T.ink3)
                        TextField("Teknoloji haberlerinde ara", text: $store.teknolojiQuery).textFieldStyle(.plain).font(.ui(12.5)).frame(width: 190)
                        if !store.teknolojiQuery.isEmpty {
                            Button { store.teknolojiQuery = "" } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(T.ink3)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(T.paper2, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(T.rule, lineWidth: 1))
                }
            }
            .padding(.init(top: 34, leading: 24, bottom: 14, trailing: 24))
            .overlay(alignment: .bottom) { Rule() }

            content
        }
    }

    @ViewBuilder private var content: some View {
        if case .failed(let m) = store.newsState, store.news.isEmpty {
            ErrorCard(eyebrow: "HATA · TEKNOLOJİ", message: m) { Task { await store.refreshNews() } }
                .frame(maxWidth: 340).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if store.news.isEmpty {
            SkeletonCard(title: "YÜKLENİYOR · TEKNOLOJİ", widths: [0.8, 0.95, 0.6, 0.9, 0.7])
                .frame(maxWidth: 340).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if store.filteredTeknoloji.isEmpty {
            let searching = !store.teknolojiQuery.trimmingCharacters(in: .whitespaces).isEmpty
            EmptyBox(title: searching ? "“\(store.teknolojiQuery)” için sonuç yok" : "Teknoloji haberi yok",
                     subtitle: searching ? "Başka bir kelime dene" : "Ayarlar'dan Webtekno, ShiftDelete.Net, Donanımhaber ya da Webrazzi'yi etkinleştir",
                     actionTitle: searching ? nil : "Kaynakları aç") { store.openSettingsAction?() }
                .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            HStack(spacing: 0) {
                NewsDayList(items: store.filteredTeknoloji, selectedID: store.selectedTeknoloji?.id) { store.selectedTeknolojiID = $0.id }
                .frame(width: 432)
                .overlay(alignment: .trailing) { VRule() }
                if let n = store.selectedTeknoloji { NewsDetail(item: n) }
            }
        }
    }
}
