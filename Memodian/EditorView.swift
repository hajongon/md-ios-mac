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
    @Environment(\.colorScheme) private var colorScheme   // ← 다크/라이트 전환을 위해 추가
    @State private var session: NoteSessionMeta?
    @State private var autosaveWork: DispatchWorkItem?
    @State private var mode: EditorMode = .edit
    @FocusState private var isEditingFocused: Bool
    @State private var didCommit = false
    
    // 우측 스크롤로 화면 전환
    @State private var dragOffsetX: CGFloat = 0
    private let swipeDismissThreshold: CGFloat = 80


    // 하이라이트 캐시 구독(리렌더 트리거에 사용)
    @ObservedObject private var hl = HLCache.shared

    // ===== 폰트 스케일링 =====
    // index 0 == 100%(최대, 초기 표시값), 뒤로 갈수록 더 작게
    // 초기값이 0.8이어서 preview 모드에서 작게 보였던 것? -> yes
    private let scaleSteps: [CGFloat] = [1, 0.9, 0.8, 0.7, 0.6]
    @State private var scaleIndex: Int = 0             // 시작이 '최대'
    @State private var baseBodyPointSize: CGFloat = 17 // iOS 기본 body 크기. onAppear에서 가져옴

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
        // 👇 스와이프 제스처용 offset
        .offset(x: dragOffsetX)
        // 👇 좌로 스와이프해서 목록으로 돌아가기
        .gesture(
            DragGesture()
                .onChanged { value in
                    // 세로로 크게 움직인 드래그는 무시 (스크롤 제스처와 충돌 방지)
                    guard abs(value.translation.height) < 40 else { return }

                    // 👉 오른쪽으로 움직일 때만 오프셋 적용 (왼쪽 스와이프는 화면 안 끌려가게)
                    if value.translation.width > 0 {
                        dragOffsetX = value.translation.width
                    } else {
                        dragOffsetX = 0
                    }
                }
                .onEnded { value in
                    if value.translation.width > swipeDismissThreshold {
                        backCommitAndDismiss()
                    } else {
                        // threshold 미만이면 원위치 복귀
                        withAnimation(.easeOut) {
                            dragOffsetX = 0
                        }
                    }
                }
        )
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // 좌측: Back
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

            // 우측: 확대/축소(공통 뷰, 모드만 전달)
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                zoomControls(isPreview: mode == .preview)
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
        
        // 프리뷰 진입 시 하이라이트 캐시 미리 준비
        // 프리뷰 진입 시 prewarm도 테마 맞춰 호출
        .onChange(of: mode) { _, new in
            if new == .preview {
                HLCache.shared.prewarm(
                    markdown: text,
                    isDark: colorScheme == .dark
                )
            }
        }

        // 편집 모드에서만 줌 전환 애니메이션
        .animation(mode == .edit ? .easeInOut : nil, value: scaleIndex)
    }

    @ViewBuilder
    private var editorBody: some View {
        if mode == .edit {
            TextEditor(text: $text)
                .font(.system(size: currentPointSize,
                              weight: .regular,
                              design: .monospaced))
                .focused($isEditingFocused)
                .padding(.horizontal)
                .onChange(of: text) { _, newValue in
                    scheduleAutosave(newValue)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        HLCache.shared.prewarm(
                            markdown: newValue,
                            isDark: colorScheme == .dark
                        )
                    }
                }
        } else {
            GeometryReader { geo in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        Markdown(text)
                            .markdownTheme(
                                previewTheme(
                                    scale: currentScale,
                                    colorScheme: colorScheme
                                )
                            )
                            .markdownCodeSyntaxHighlighter(
                                HighlightSwiftAdapter(
                                    isDark: colorScheme == .dark
                                )
                            )
                            .textSelection(.enabled)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(width: geo.size.width, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .id("preview-\(scaleIndex)-\(hl.version)-\(mode)-\(colorScheme == .dark ? "dark" : "light")")
            }
        }
    }
    


    // 공통 확대/축소 버튼
    @ViewBuilder
    private func zoomControls(isPreview: Bool) -> some View {
        HStack(spacing: 0) {
            Button {
                if canZoomOut { scaleIndex += 1 }
            } label: {
                Text("–")
                    .font(.system(size: 18, weight: .semibold))
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
            }
            .disabled(!canZoomOut)
            .accessibilityLabel(isPreview ? "Zoom Out (Preview)" : "Font Smaller (Edit)")

            Button {
                if canZoomIn { scaleIndex -= 1 }
            } label: {
                Text("+")
                    .font(.system(size: 18, weight: .semibold))
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
            }
            .disabled(!canZoomIn)
            .accessibilityLabel(isPreview ? "Zoom In (Preview)" : "Font Larger (Edit)")
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
