import SwiftUI

/// Arşiv: stories bookmarked from Haberler, Teknoloji or any related-news list. Same two-pane reading
/// layout as Haberler, grouped by the story's day. Bookmarks keep the full item, so they outlive the
/// one-week news window and stay readable after the story has dropped out of its feed.
struct ArsivView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Arşiv").font(.serif(25)).tracking(-0.4)
                    Spacer()
                    Text(store.arsivQuery.trimmingCharacters(in: .whitespaces).isEmpty
                         ? "\(store.bookmarks.count) haber"
                         : "\(store.filteredArsiv.count) sonuç").font(.mono(11, .regular)).foregroundStyle(T.ink3)
                }
                HStack(spacing: 8) {
                    if !isPhone {
                        Text("Haberlerde ya da detayda “Arşive ekle” ile kaydettiklerin")
                            .font(.ui(12)).foregroundStyle(T.ink3)
                        Spacer(minLength: 8)
                    }
                    HStack(spacing: 6) {
                        Text("⌕").font(.ui(13)).foregroundStyle(T.ink3)
                        TextField("Arşivde ara", text: $store.arsivQuery).textFieldStyle(.plain).font(.ui(12.5)).frame(width: isPhone ? nil : 170)
                        if !store.arsivQuery.isEmpty {
                            Button { store.arsivQuery = "" } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(T.ink3)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(T.paper2, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(T.rule, lineWidth: 1))
                }
            }
            .padding(.screenHeader)
            .overlay(alignment: .bottom) { Rule() }

            content
        }
    }

    @ViewBuilder private var content: some View {
        if store.bookmarks.isEmpty {
            EmptyBox(title: "Arşivin boş",
                     subtitle: "Bir haberi açıp “Arşive ekle”ye bas ya da listede sağ tıkla",
                     actionTitle: "Haberlere git") { store.screen = .haberler }
                .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if store.filteredArsiv.isEmpty {
            EmptyBox(title: "“\(store.arsivQuery)” için sonuç yok", subtitle: "Başka bir kelime dene").padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            NewsFeedPane(items: store.filteredArsiv, selected: store.selectedArsiv, fold: false) { store.selectedArsivID = $0.id }
        }
    }
}
