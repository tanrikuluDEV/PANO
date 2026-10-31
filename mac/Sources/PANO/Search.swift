import SwiftUI

/// Search text folded once for cheap matching: lowercase, accents dropped, Turkish dotless ı → i.
/// Lists compare a folded query against folded text with a plain substring check instead of a
/// case/diacritic-insensitive `range(of:)` per story per keystroke.
enum Search {
    private static let tr = Locale(identifier: "tr_TR")
    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: tr).replacingOccurrences(of: "ı", with: "i")
    }
}

/// "⌕ … ara" box. The typed text lives here, so every key shows up at once; the list behind it is only
/// re-filtered once typing pauses (clearing applies immediately). Changes made elsewhere to `text`
/// (a category pill clearing it, a topic link filling it) are picked up.
struct SearchBox: View {
    let placeholder: String
    @Binding var text: String
    var width: CGFloat? = nil
    var fontSize: CGFloat = 12.5
    var delay: Double = 0.25
    /// The phone's taller box: magnifying glass, 15 pt text, rounder corners.
    var large = false
    @State private var draft = ""

    var body: some View {
        let radius: CGFloat = large ? 10 : 7
        HStack(spacing: 6) {
            if large { Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(T.ink3) }
            else { Text("⌕").font(.ui(13)).foregroundStyle(T.ink3) }
            TextField(placeholder, text: $draft).textFieldStyle(.plain).font(.ui(large ? 15 : fontSize)).frame(width: width)
                .submitLabel(.search)
                .onSubmit { text = draft }
            if !draft.isEmpty {
                Button { draft = ""; text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: large ? 15 : 12)).foregroundStyle(T.ink3)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, large ? 12 : 10).padding(.vertical, large ? 9 : 5)
        .background(T.paper2, in: RoundedRectangle(cornerRadius: radius))
        .overlay(RoundedRectangle(cornerRadius: radius).stroke(T.rule, lineWidth: 1))
        .onAppear { draft = text }
        .onChange(of: text) { _, new in if new != draft { draft = new } }
        .task(id: draft) {
            guard draft != text else { return }
            if !draft.trimmingCharacters(in: .whitespaces).isEmpty {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
            }
            text = draft
        }
    }
}
