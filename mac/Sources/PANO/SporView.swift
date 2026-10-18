import SwiftUI

/// Spor tab: news from every sports branch, not just football. Same two-pane reading layout as Haberler, with
/// branch pills (each showing its current count), a source menu and search. Scores and fixtures live in Maçlar.
struct SporView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        let searching = !store.sporQuery.trimmingCharacters(in: .whitespaces).isEmpty
        let counts = store.sporBranchCounts
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text("Spor").font(.serif(25)).tracking(-0.4)
                    Spacer(minLength: 12)
                    Menu {
                        Button("Tümü") { store.sporSourceFilter = nil }
                        Divider()
                        ForEach(store.sporSources) { s in Button(s.name) { store.sporSourceFilter = s.id } }
                    } label: {
                        Text("Kaynak: \(allNewsSources.first { $0.id == store.sporSourceFilter }?.name ?? "Tümü") ▾")
                            .font(.ui(12)).foregroundStyle(T.ink2).lineLimit(1)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(T.paper2, in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(T.rule, lineWidth: 1))
                    }.menuStyle(.button).buttonStyle(.plain).fixedSize()
                    HStack(spacing: 6) {
                        Text("⌕").font(.ui(13)).foregroundStyle(T.ink3)
                        TextField("Spor haberlerinde ara", text: $store.sporQuery).textFieldStyle(.plain).font(.ui(12.5)).frame(width: 160)
                        if !store.sporQuery.isEmpty {
                            Button { store.sporQuery = "" } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(T.ink3)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(T.paper2, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(T.rule, lineWidth: 1))
                }
                // branches get a row of their own: seven pills with counts don't share a line with menu + search
                HStack(spacing: 8) {
                    Group {
                        Button { store.sporQuery = ""; store.sporBranch = nil } label: {
                            Pill(text: "Tümü", selected: store.sporBranch == nil)
                        }.buttonStyle(.plain)
                        ForEach(SportBranch.allCases) { b in
                            let n = counts[b] ?? 0
                            Button { store.sporQuery = ""; store.sporBranch = b } label: {
                                Pill(text: n > 0 ? "\(b.rawValue) \(n)" : b.rawValue, selected: store.sporBranch == b)
                            }
                            .buttonStyle(.plain)
                            .opacity(n > 0 || store.sporBranch == b ? 1 : 0.5)
                        }
                    }
                    .opacity(searching ? 0.4 : 1)
                    Spacer(minLength: 8)
                    Text(searching ? "\(store.filteredSpor.count) sonuç" : "\(store.filteredSpor.count) başlık · \(store.sporSources.count) kaynak")
                        .font(.mono(11, .regular)).foregroundStyle(T.ink3).lineLimit(1).fixedSize()
                }
            }
            .padding(.init(top: 34, leading: 24, bottom: 14, trailing: 24))
            .overlay(alignment: .bottom) { Rule() }

            content(searching: searching)
        }
    }

    @ViewBuilder private func content(searching: Bool) -> some View {
        if case .failed(let m) = store.newsState, store.news.isEmpty {
            ErrorCard(eyebrow: "HATA · SPOR", message: m) { Task { await store.refreshNews() } }
                .frame(maxWidth: 340).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if store.news.isEmpty {
            SkeletonCard(title: "YÜKLENİYOR · SPOR", widths: [0.8, 0.95, 0.6, 0.9, 0.7])
                .frame(maxWidth: 340).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if store.filteredSpor.isEmpty {
            EmptyBox(title: searching ? "“\(store.sporQuery)” için sonuç yok"
                                      : store.sporBranch.map { "Bu hafta \($0.rawValue.lowercased(with: Locale(identifier: "tr_TR"))) haberi yok" } ?? "Spor haberi yok",
                     subtitle: searching ? "Başka bir kelime dene" : "Başka bir branş ya da kaynak dene, veya Ayarlar'dan spor kaynaklarını aç",
                     actionTitle: searching ? nil : "Kaynakları aç") { store.openSettingsAction?() }
                .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            HStack(spacing: 0) {
                NewsDayList(items: store.filteredSpor, selectedID: store.selectedSpor?.id) { store.selectedSporID = $0.id }
                    .frame(width: 432)
                    .overlay(alignment: .trailing) { VRule() }
                if let n = store.selectedSpor { NewsDetail(item: n) }
            }
        }
    }
}
