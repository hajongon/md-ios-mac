import SwiftUI
import MarkdownUI

enum EditorMode: String, CaseIterable, Identifiable {
    case edit = "Edit"
    case preview = "Preview"
    var id: String { rawValue }
}

struct EditorView: View {
    @Binding var text: String
    let originalURL: URL
    var onCommitted: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var session: NoteSessionMeta?
    @State private var autosaveWork: DispatchWorkItem?
    @State private var mode: EditorMode = .edit
    @FocusState private var isEditingFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                ForEach(EditorMode.allCases) { m in
                    Text(m.rawValue).tag(m as EditorMode)
                }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top])

            editorBody

            HStack {
                Spacer()
                Button("Save") { commitOriginalWins() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: [.command])
                    .padding()
            }
        }
        .navigationTitle(mode == .edit ? "Edit" : "Preview")
        .onAppear(perform: startIfNeeded)
        .onDisappear { autosaveWork?.cancel() }
    }

    @ViewBuilder
    private var editorBody: some View {
        if mode == .edit {
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .focused($isEditingFocused)
                .padding(.horizontal)
                // ✅ iOS 17+ 권장 구문
                .onChange(of: text) { oldValue, newValue in
                    scheduleAutosave(newValue)
                }
        } else {
            ScrollView {
                Markdown(text)
                    .markdownTheme(.gitHub)
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func startIfNeeded() {
        guard session == nil else { return }
        session = try? CacheManager.shared.beginEditing(original: originalURL)
        if let s = session {
            text = (try? String(contentsOf: s.cacheURL, encoding: .utf8)) ?? text
        }
        isEditingFocused = true
    }

    private func scheduleAutosave(_ newValue: String) {
        autosaveWork?.cancel()
        let work = DispatchWorkItem { [session] in
            if let s = session {
                CacheManager.shared.autosave(text: newValue, to: s.cacheURL)
            }
        }
        autosaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func commitOriginalWins() {
        guard let s = session else { return }
        do {
            try CacheManager.shared.commit(s, policy: .originalWins)
            onCommitted()
            dismiss()
        } catch {
            print("Commit error:", error)
        }
    }
}
