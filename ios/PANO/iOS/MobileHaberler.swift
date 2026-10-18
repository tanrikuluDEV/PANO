import SwiftUI

/// Haberler on the phone: the list fills the screen and a story opens on its own page (the Mac shows both side by side).
/// Runs inside the shell's navigation stack.
struct MobileHaberler: View {
    @Environment(AppStore.self) private var store
    @State private var pushed: NewsItem?

    var body: some View {
        VStack(spacing: 0) {
            controls
            content
        }
        .navigationDestination(item: $pushed) { NewsDetail(item: $0) }
        // a story opened elsewhere (Bugün, a topic card, a notification) arrives as `selectedNewsID`
        .onChange(of: store.pendingNewsID) { _, id in if let id { store.pendingNewsID = nil; open(id) } }
        .onAppear { if let id = store.pendingNewsID { store.pendingNewsID = nil; open(id) } }
    }

    private func open(_ id: String?) {
        guard let id, pushed?.id != id, let n = store.news.first(where: { $0.id == id }) else { return }
        pushed = n
    }

    private var controls: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Haberler").font(.serif(25)).tracking(-0.4)
                Spacer()
                if store.newsMode == .list {
                    Text("\(store.filteredNews.count) başlık").font(.mono(11, .regular)).foregroundStyle(T.ink3)
                }
            }
            .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                ModeSwitch(selection: $store.newsMode, options: [(.list, "Liste"), (.morning, "Sabah Özeti"), (.daily, "Günün Özeti"), (.weekly, "Haftanın Özeti")])
                    .padding(.horizontal, 16)
            }
            if store.newsMode == .list {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(T.ink3)
                    TextField("Haberlerde ara", text: $store.newsQuery).textFieldStyle(.plain).font(.ui(15)).submitLabel(.search)
                    if !store.newsQuery.isEmpty {
                        Button { store.newsQuery = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(T.ink3) }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(T.paper2, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(T.rule, lineWidth: 1))
                .padding(.horizontal, 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(newsCategories, id: \.self) { k in
                            Button { store.newsQuery = ""; store.newsCategory = k } label: { Pill(text: k, selected: store.newsCategory == k) }.buttonStyle(.plain)
                        }
                        Menu {
                            Button("Tümü") { store.newsSourceFilter = nil }
                            Divider()
                            ForEach(store.activeSources) { s in Button(s.name) { store.newsSourceFilter = s.id } }
                        } label: {
                            Text("Kaynak: \(allNewsSources.first { $0.id == store.newsSourceFilter }?.name ?? "Tümü") ▾")
                                .font(.ui(12)).foregroundStyle(T.ink2)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(T.paper2, in: RoundedRectangle(cornerRadius: 7))
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.top, 4).padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rule() }
    }

    @ViewBuilder private var content: some View {
        if store.newsMode == .morning {
            ScrollView {
                MorningBriefView().padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 24)
            }
            .refreshable { await store.refreshSlow(force: true) }
        } else if store.newsMode == .daily, !store.news.isEmpty {
            GununOzetiView()
        } else if store.newsMode == .weekly, !store.news.isEmpty {
            HaftaninOzetiView()
        } else if case .failed(let m) = store.newsState, store.news.isEmpty {
            ErrorCard(eyebrow: "HATA · HABERLER", message: m) { Task { await store.refreshNews() } }.padding(16)
            Spacer()
        } else if store.news.isEmpty {
            SkeletonCard(title: "YÜKLENİYOR · HABERLER", widths: [0.8, 0.95, 0.6, 0.9, 0.7]).padding(16)
            Spacer()
        } else if store.filteredNews.isEmpty {
            EmptyBox(title: "Sonuç yok", subtitle: "Başka bir kategori, kaynak ya da kelime dene").padding(16)
            Spacer()
        } else {
            let mark = store.newsQuery.trimmingCharacters(in: .whitespaces).isEmpty ? store.newsReadMark : nil
            NewsDayList(items: store.filteredNews, selectedID: nil, readMark: mark) { n in
                pushed = n
                store.selectedNewsID = n.id
            }
            .refreshable { await store.refreshNews() }
        }
    }
}
