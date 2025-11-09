//
//  EditorView.swift
//  Memodian
//
//  Created by hajongon on 11/5/25.
//

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
    @State private var didCommit = false

    // NEW: 캐시 옵저빙(버전 변화 감지)
    @ObservedObject private var hlCache = HLCache.shared

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
        }
        // .navigationTitle(mode == .edit ? "Edit" : "Preview")
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { backCommitAndDismiss() } label: {
                    Image(systemName: "chevron.left")
                        .imageScale(.medium)
                        .font(.system(size: 17, weight: .semibold))
                        .padding(.trailing, 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }
        }
        .onAppear(perform: startIfNeeded)
        .onDisappear {
            autosaveWork?.cancel()
            backCommitAndDismiss()
        }
        // NEW: 프리뷰로 바뀌는 시점에 코드블록을 미리 하이라이트
        .onChange(of: mode) { old, new in
            if new == .preview {
                HLCache.shared.prewarm(markdown: text)
            }
        }
    }

    @ViewBuilder
    private var editorBody: some View {
        if mode == .edit {
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .focused($isEditingFocused)
                .padding(.horizontal)
                .onChange(of: text) { _, newValue in
                    scheduleAutosave(newValue)
                    // 선택: 짧은 지연 후 프리워밍
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        HLCache.shared.prewarm(markdown: newValue)
                    }
                }

        } else {
            ScrollView {
                Markdown(text)
                    .markdownTheme(.gitHub)
                    .markdownCodeSyntaxHighlighter(HighlightSwiftAdapter())
                    .textSelection(.enabled)
                    .padding()
                    // NEW: 캐시가 채워질 때마다 id가 바뀌어 첫 프레임 이후 즉시 리렌더
                    .id(hlCache.version)
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

    private func backCommitAndDismiss() {
        commitOriginalWins()
        // dismiss는 commit 내부에서 호출
    }

    private func commitOriginalWins() {
        guard !didCommit else { return }
        didCommit = true

        guard let s = session else {
            dismiss()
            return
        }
        do {
            try CacheManager.shared.commit(s, policy: .originalWins)
            onCommitted()
            dismiss()
        } catch {
            print("Commit error:", error)
            dismiss()
        }
    }
}
