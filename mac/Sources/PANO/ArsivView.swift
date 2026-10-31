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
                    Text("Haberlerde ya da detayda “Arşive ekle” ile kaydettiklerin")
                        .font(.ui(12)).foregroundStyle(T.ink3)
                    Spacer(minLength: 8)
                    SearchBox(placeholder: "Arşivde ara", text: $store.arsivQuery, width: 170)
                }
            }
            .padding(.init(top: 34, leading: 24, bottom: 14, trailing: 24))
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
            HStack(spacing: 0) {
                NewsDayList(items: store.filteredArsiv, selectedID: store.selectedArsiv?.id, fold: false) { store.selectedArsivID = $0.id }
                    .frame(width: 432)
                    .overlay(alignment: .trailing) { VRule() }
                if let n = store.selectedArsiv { NewsDetail(item: n) }
            }
        }
    }
}
