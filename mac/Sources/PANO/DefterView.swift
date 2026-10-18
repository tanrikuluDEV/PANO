import SwiftUI
import AppKit

struct DefterView: View {
    @Environment(AppStore.self) private var store
    @State private var month = Day.cal.dateInterval(of: .month, for: Date())!.start

    var body: some View {
        HStack(spacing: 0) {
            leftColumn.frame(width: 228)
            EntryEditor(day: store.journalDay).id(store.journalDay).frame(maxWidth: .infinity)
        }
    }

    private var leftColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(Day.format(month, "LLLL yyyy").capitalized(with: Locale(identifier: "tr_TR"))).font(.serif(15))
                    Spacer()
                    HStack(spacing: 8) {
                        Button { shiftMonth(-1) } label: { Text("‹") }
                        Button { shiftMonth(1) } label: { Text("›") }
                    }.buttonStyle(.plain).font(.mono(13, .regular)).foregroundStyle(T.ink3)
                }.padding(.horizontal, 4)
                calendar
                Rule()
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: "SON SAYFALAR", size: 9.5).padding(.horizontal, 6).padding(.bottom, 4)
                    let recent = store.journal.values.filter { !$0.text.isEmpty }.sorted { $0.day > $1.day }.prefix(6)
                    if recent.isEmpty { Text("Henüz sayfa yok").font(.ui(12)).foregroundStyle(T.ink3).padding(.horizontal, 6) }
                    ForEach(Array(recent), id: \.day) { e in
                        let sel = e.day == store.journalDay
                        Button { store.journalDay = e.day; if let d = Day.date(e.day) { month = Day.cal.dateInterval(of: .month, for: d)!.start } } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(Day.format(Day.date(e.day) ?? Date(), "d MMMM")).font(.mono(11)).foregroundStyle(sel ? T.accent : T.ink2)
                                Text(e.text.split(separator: "\n").first.map(String.init) ?? "").font(.ui(12)).foregroundStyle(T.ink2).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                            .background(sel ? T.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 7)).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(.horizontal, 12).padding(.top, 40).padding(.bottom, 16)
        }
        .overlay(alignment: .trailing) { VRule() }
    }

    private func shiftMonth(_ n: Int) { month = Day.cal.date(byAdding: .month, value: n, to: month) ?? month }

    private var calendar: some View {
        let cal = Day.cal
        let first = month
        let days = cal.range(of: .day, in: .month, for: first)!.count
        let lead = (cal.component(.weekday, from: first) + 5) % 7   // Monday-first
        let cols = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        return LazyVGrid(columns: cols, spacing: 2) {
            ForEach(["Pt", "Sa", "Ça", "Pe", "Cu", "Ct", "Pz"], id: \.self) { Text($0).font(.mono(9)).foregroundStyle(T.ink3).frame(height: 18) }
            ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 26) }
            ForEach(1...days, id: \.self) { d in
                let date = cal.date(byAdding: .day, value: d - 1, to: first)!
                let key = Day.key(date)
                let isToday = key == Day.key(), isSel = key == store.journalDay
                let written = !(store.entry(key)?.text.isEmpty ?? true)
                Button { store.journalDay = key } label: {
                    Text("\(d)").font(.mono(11))
                        .foregroundStyle(isToday ? T.accentInk : written ? T.accent : T.ink2)
                        .frame(maxWidth: .infinity).frame(height: 26)
                        .background(isToday ? T.accent : written ? T.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(isSel && !isToday ? T.accent : .clear, lineWidth: 1))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }
}

struct EntryEditor: View {
    @Environment(AppStore.self) private var store
    let day: String
    @State private var text = ""
    @State private var addingTag = false
    @State private var tagDraft = ""
    @State private var todoDraft = ""
    @State private var saveTask: Task<Void, Never>?

    private var date: Date { Day.date(day) ?? Date() }
    private var words: Int { text.split { $0.isWhitespace || $0.isNewline }.count }

    var body: some View {
        ScrollView {
            HStack { Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 22) {
                    header
                    todosSection
                    journalSection
                }.frame(maxWidth: 640)
                Spacer(minLength: 0)
            }.padding(.init(top: 40, leading: 24, bottom: 48, trailing: 24))
        }
        .background(T.paper2)
        .onAppear { text = store.entry(day)?.text ?? "" }
        .onDisappear { flush() }
    }

    private var header: some View {
        let e = store.entry(day)
        let doy = Day.cal.ordinality(of: .day, in: .year, for: date) ?? 0
        return HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Day.long(date)).font(.serif(27)).tracking(-0.4)
                Text("PANO · \(doy). gün" + (e.map { " · \(Day.hm($0.savedAt))'te kaydedildi" } ?? "")).font(.mono(11, .regular)).foregroundStyle(T.ink3)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(e?.tags ?? [], id: \.self) { t in
                    Tag(text: t, accent: true).contextMenu { Button("Etiketi kaldır") { store.removeTag(t, day: day) } }
                }
                if addingTag {
                    TextField("etiket", text: $tagDraft).textFieldStyle(.plain).font(.mono(10.5, .regular)).frame(width: 70)
                        .padding(.horizontal, 9).padding(.vertical, 5).background(T.paper3, in: RoundedRectangle(cornerRadius: 6))
                        .onSubmit { store.addTag(tagDraft, day: day); tagDraft = ""; addingTag = false }
                } else {
                    Button { addingTag = true } label: { Tag(text: "+ etiket") }.buttonStyle(.plain)
                }
            }
        }
        .padding(.bottom, 12).overlay(alignment: .bottom) { Rule() }
    }

    private var todosSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "YAPILACAKLAR", link: "Kalanları yarına aktar →") { store.moveRemainingToTomorrow(from: day) }
            VStack(spacing: 0) {
                ForEach(store.todos(on: day)) { TodoRow(todo: $0, roomy: true, showMove: true) }
                HStack(spacing: 11) {
                    Text("+").font(.ui(11)).foregroundStyle(T.ink3).frame(width: 16, height: 16)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(T.rule, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])))
                    TextField("Bu güne görev ekle", text: $todoDraft).textFieldStyle(.plain).font(.ui(13.5))
                        .onSubmit { store.addTodo(todoDraft, day: day); todoDraft = "" }
                }.padding(.vertical, 9).padding(.horizontal, 2)
            }
        }
    }

    private var journalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "GÜNLÜK")
            RuledEditor(text: $text)
                .frame(minHeight: 300)
                .background(RoundedRectangle(cornerRadius: 10).stroke(T.rule, lineWidth: 1))
                .onChange(of: text) { scheduleSave() }
            HStack {
                Text("\(words) kelime · otomatik kaydedilir").font(.mono(10.5, .regular)).foregroundStyle(T.ink3)
                Spacer()
                Button("⌘S ile kaydet") { flush() }.buttonStyle(.plain).keyboardShortcut("s", modifiers: .command)
                    .font(.mono(10.5, .regular)).foregroundStyle(T.ink3)
            }
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { try? await Task.sleep(nanoseconds: 600_000_000); if !Task.isCancelled { flush() } }
    }
    private func flush() {
        saveTask?.cancel()
        if text != (store.entry(day)?.text ?? "") { store.setText(text, day: day) }
    }
}

/// NSTextView with a fixed 31pt line height so the text sits exactly on the ruled lines.
struct RuledEditor: NSViewRepresentable {
    @Binding var text: String
    static let lineHeight: CGFloat = 31

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> RuledTextView {
        let v = RuledTextView()
        v.delegate = context.coordinator
        v.drawsBackground = false
        v.isRichText = false
        v.allowsUndo = true
        v.textContainerInset = NSSize(width: 22, height: 20)
        v.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        v.isVerticallyResizable = true
        v.isHorizontallyResizable = false
        v.autoresizingMask = [.width]
        v.textContainer?.widthTracksTextView = true
        v.applyStyle()
        v.string = text
        return v
    }

    func updateNSView(_ v: RuledTextView, context: Context) {
        v.applyStyle()
        if v.string != text { v.string = text; v.applyStyle() }
        v.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RuledEditor
        init(_ p: RuledEditor) { parent = p }
        func textDidChange(_ n: Notification) {
            guard let v = n.object as? NSTextView else { return }
            parent.text = v.string
        }
    }
}

final class RuledTextView: NSTextView {
    func applyStyle() {
        let ps = NSMutableParagraphStyle()
        ps.minimumLineHeight = RuledEditor.lineHeight; ps.maximumLineHeight = RuledEditor.lineHeight
        let font = NSFont(name: Fonts.petrona ? "Petrona" : "Georgia", size: 16) ?? .systemFont(ofSize: 16)
        let ink = NSColor(T.ink)
        typingAttributes = [.font: font, .foregroundColor: ink, .paragraphStyle: ps]
        defaultParagraphStyle = ps
        insertionPointColor = NSColor(T.accent)
        if let ts = textStorage, ts.length > 0 {
            ts.addAttributes([.font: font, .foregroundColor: ink, .paragraphStyle: ps], range: NSRange(location: 0, length: ts.length))
        }
    }

    override var intrinsicContentSize: NSSize {
        guard let lm = layoutManager, let tc = textContainer else { return super.intrinsicContentSize }
        lm.ensureLayout(for: tc)
        return NSSize(width: NSView.noIntrinsicMetric, height: max(300, lm.usedRect(for: tc).height + textContainerInset.height * 2))
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }

    override func draw(_ dirtyRect: NSRect) {
        let h = RuledEditor.lineHeight
        let top = textContainerInset.height
        NSColor(T.rule2).setFill()
        var y = top + h - 1
        while y < bounds.height {
            NSRect(x: 0, y: y, width: bounds.width, height: 1).fill()
            y += h
        }
        super.draw(dirtyRect)
    }
}
