// EditorView.swift

import SwiftUI
import MarkdownUI
#if canImport(UIKit)
import UIKit
#endif

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

    // 캐시 옵저빙(버전 변화 감지)
    @ObservedObject private var hlCache = HLCache.shared

    // ===== 폰트 스케일링 =====
    // index 0 == 100%(최대, 초기 표시값), 뒤로 갈수록 더 작게
    private let scaleSteps: [CGFloat] = [0.8, 0.7, 0.6, 0.5]
    @State private var scaleIndex: Int = 0             // 시작이 '최대'
    @State private var baseBodyPointSize: CGFloat = 17 // iOS 기본 body 크기. onAppear에서 가져옴

    // Preview 리렌더 강제용 키
    @State private var previewRerenderKey: Int = 0

    private var currentScale: CGFloat { scaleSteps[scaleIndex] }
    private var currentPointSize: CGFloat { baseBodyPointSize * currentScale }
    private var canZoomOut: Bool { scaleIndex < scaleSteps.count - 1 } // 더 작게(–)
    private var canZoomIn:  Bool { scaleIndex > 0 }                    // 더 크게(+), 최대는 0

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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // 좌측: 공통 Back
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

            // 우측: 편집 모드 전용 확대/축소
            if mode == .edit {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        if canZoomOut { scaleIndex += 1 }
                    } label: {
                        Text("–")
                            .font(.system(size: 18, weight: .semibold))
                            .padding(.horizontal, 4)
                            .contentShape(Rectangle())
                    }
                    .disabled(!canZoomOut)
                    .accessibilityLabel("Font Smaller (Edit)")

                    Button {
                        if canZoomIn { scaleIndex -= 1 }
                    } label: {
                        Text("+")
                            .font(.system(size: 18, weight: .semibold))
                            .padding(.horizontal, 4)
                            .contentShape(Rectangle())
                    }
                    .disabled(!canZoomIn)
                    .accessibilityLabel("Font Larger (Edit)")
                }
            }

            // 우측: 프리뷰 모드 전용 확대/축소 (브라우저 줌 느낌)
            if mode == .preview {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        if canZoomOut {
                            scaleIndex += 1
                            previewRerenderKey &+= 1
                        }
                    } label: {
                        Text("–")
                            .font(.system(size: 18, weight: .semibold))
                            .padding(.horizontal, 4)
                            .contentShape(Rectangle())
                    }
                    .disabled(!canZoomOut)
                    .accessibilityLabel("Zoom Out (Preview)")

                    Button {
                        if canZoomIn {
                            scaleIndex -= 1
                            previewRerenderKey &+= 1
                        }
                    } label: {
                        Text("+")
                            .font(.system(size: 18, weight: .semibold))
                            .padding(.horizontal, 4)
                            .contentShape(Rectangle())
                    }
                    .disabled(!canZoomIn)
                    .accessibilityLabel("Zoom In (Preview)")
                }
            }
        }
        .onAppear {
            startIfNeeded()
            #if canImport(UIKit)
            baseBodyPointSize = UIFont.preferredFont(forTextStyle: .body).pointSize
            #endif
        }
        .onDisappear {
            autosaveWork?.cancel()
            backCommitAndDismiss()
        }
        // 폰트 스케일 변화 감지 (프리뷰 강제 리렌더)
        .onChange(of: scaleIndex) { _, newIndex in
            previewRerenderKey &+= 1
            // 디버그 로그
            print("🔁 onChange scaleIndex → \(newIndex), previewRerenderKey=\(previewRerenderKey)")
        }
        // 프리뷰 진입 시 하이라이트 미리 준비(있으면 활용)
        .onChange(of: mode) { _, new in
            if new == .preview {
                HLCache.shared.prewarm(markdown: text) // 프로젝트에 있는 경우만 동작
            }
        }
        // .animation(.easeInOut, value: scaleIndex) // 줌 전환 부드럽게
        // 전체에는 애니메이션 X, 편집 모드일 때만 필요하다면:
        .animation(mode == .edit ? .easeInOut : nil, value: scaleIndex)

    }

    @ViewBuilder
    private var editorBody: some View {
        if mode == .edit {
            TextEditor(text: $text)
                .font(.system(size: currentPointSize, weight: .regular, design: .monospaced))
                .focused($isEditingFocused)
                .padding(.horizontal)
                .onChange(of: text) { _, newValue in
                    scheduleAutosave(newValue)
                    // 짧은 지연 후 프리워밍(있을 때만)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        HLCache.shared.prewarm(markdown: newValue)
                    }
                }
        }
        else {
            GeometryReader { geo in
                ScrollView([.vertical, .horizontal]) {
                    VStack(alignment: .leading, spacing: 0) {
                        Markdown(text)
                            .markdownTheme(.gitHub)
                            .markdownCodeSyntaxHighlighter(HighlightSwiftAdapter())
                            .textSelection(.enabled)
                            .padding()
                    }
                    // 렌더는 스케일링하되,
                    // 레이아웃 폭은 1/scale 배로 늘려서 잘림 방지
                    .scaleEffect(currentScale, anchor: .topLeading)
                    .frame(width: geo.size.width / max(currentScale, 0.001), alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true) // 내부 높이 자연 확장
                }
                .id("preview-\(previewRerenderKey)-\(scaleIndex)")
                .onAppear {
                    print("🪶 preview appear → key=\(previewRerenderKey), scaleIndex=\(scaleIndex)")
                }
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
