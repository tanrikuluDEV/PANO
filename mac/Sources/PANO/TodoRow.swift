import SwiftUI

/// One to-do line. Click the pencil (or double-click) to edit the title, time and a free-text note inline.
struct TodoRow: View {
    @Environment(AppStore.self) private var store
    let todo: TodoItem
    var roomy = false        // Defter page: wider rows with a rule underneath
    var showMove = false     // "Yarına aktar" shortcut
    @State private var editing = false
    @State private var hovering = false
    @State private var title = ""
    @State private var time = ""
    @State private var note = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        Group { if editing { editor } else { display } }
            .onHover { hovering = $0 }
    }

    // MARK: Display

    private var display: some View {
        HStack(alignment: .top, spacing: roomy ? 11 : 10) {
            Button { store.toggle(todo.id) } label: {
                Checkbox(checked: todo.done, size: roomy ? 16 : 15).padding(.top, 1).contentShape(Rectangle())
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                Text(todo.title).font(.ui(roomy ? 13.5 : 13)).strikethrough(todo.done)
                    .foregroundStyle(todo.done ? T.ink3 : T.ink).fixedSize(horizontal: false, vertical: true)
                if let n = todo.note, !n.isEmpty {
                    Text(n).font(.ui(11.5)).foregroundStyle(T.ink3).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 6)
            if let t = todo.time, !t.isEmpty { Text(t).font(.mono(10, .regular)).foregroundStyle(T.ink3).padding(.top, 2) }
            if showMove, !todo.done {
                Button { store.moveToTomorrow(todo.id) } label: { Text("Yarına aktar").font(.ui(11.5)).foregroundStyle(T.ink3) }.buttonStyle(.plain)
            }
            Button(action: startEditing) {
                Image(systemName: "pencil").font(.system(size: 11)).foregroundStyle(T.ink3)
                    .frame(width: 20, height: 18).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Düzenle")
            .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, roomy ? 2 : 13).padding(.vertical, roomy ? 9 : 7)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: startEditing)
        .overlay(alignment: .bottom) { if roomy { Rule(color: T.rule2) } }
        .contextMenu {
            Button("Düzenle", action: startEditing)
            Button("Sil", role: .destructive) { store.deleteTodo(todo.id) }
        }
    }

    // MARK: Editor

    private var editor: some View {
        VStack(alignment: .leading, spacing: 9) {
            TextField("Görev", text: $title).textFieldStyle(.plain).font(.ui(13.5, .semibold))
                .focused($titleFocused).onSubmit(save)
            TextField("Not ekle…", text: $note, axis: .vertical).textFieldStyle(.plain).font(.ui(12.5))
                .foregroundStyle(T.ink2).lineLimit(2...6)
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "clock").font(.system(size: 10)).foregroundStyle(T.ink3)
                    TextField("Saat", text: $time).textFieldStyle(.plain).font(.mono(11, .regular)).frame(width: 52)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(T.paper3, in: RoundedRectangle(cornerRadius: 6))
                Spacer()
                Button("Sil") { store.deleteTodo(todo.id) }.foregroundStyle(T.down)
                Button("İptal") { editing = false }.foregroundStyle(T.ink2)
                Button(action: save) {
                    Text("Kaydet").font(.ui(12, .semibold)).foregroundStyle(T.accentInk)
                        .padding(.horizontal, 11).padding(.vertical, 5).background(T.accent, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .buttonStyle(.plain).font(.ui(12))
        }
        .padding(10)
        .background(T.paper, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(T.accent.opacity(0.6), lineWidth: 1))
        .padding(.horizontal, roomy ? 0 : 8).padding(.vertical, 5)
        .onExitCommand { editing = false }
    }

    private func startEditing() {
        title = todo.title; time = todo.time ?? ""; note = todo.note ?? ""
        editing = true
        DispatchQueue.main.async { titleFocused = true }
    }

    private func save() {
        store.updateTodo(todo.id, title: title, time: time, note: note)
        editing = false
    }
}
