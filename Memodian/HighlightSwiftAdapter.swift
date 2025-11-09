//
//  HighlightSwiftAdapter.swift
//  Memodian
//
//  Created by hajongon on 11/9/25.
//



import SwiftUI
import MarkdownUI
import HighlightSwift

@MainActor
final class HLCache: ObservableObject {
    static let shared = HLCache()

    @Published var store: [String: AttributedString] = [:]
    @Published var version: Int = 0 // NEW: 캐시 변경 감지를 위한 버전 카운터

    private let highlighter = Highlight()

    private func key(for code: String, lang: String?) -> String {
        (lang ?? "auto") + "#" + String(code.hashValue)
    }

    func get(code: String, lang: String?) -> AttributedString? {
        store[key(for: code, lang: lang)]
    }

    func ensure(code: String, lang: String?) {
        let k = key(for: code, lang: lang)
        guard store[k] == nil else { return }

        Task {
            do {
                let attr: AttributedString
                if let lang, !lang.isEmpty {
                    attr = try await highlighter.attributedText(code, language: lang)
                } else {
                    attr = try await highlighter.attributedText(code)
                }
                store[k] = attr
                version &+= 1          // NEW: 하이라이트 완료 → 버전 증가로 뷰 리렌더 트리거
            } catch {
                // 실패 시 plain 유지
            }
        }
    }

    // NEW: 간단한 코드블록 스캐너(```lang ... ```), 프리뷰 전에 미리 ensure 호출
    func prewarm(markdown: String) {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        var i = 0
        while i < lines.count {
            let line = String(lines[i])
            if line.hasPrefix("```") {
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code = ""
                i += 1
                while i < lines.count, !String(lines[i]).hasPrefix("```") {
                    code.append(String(lines[i]))
                    code.append("\n")
                    i += 1
                }
                ensure(code: code, lang: lang.isEmpty ? nil : lang)
            }
            i += 1
        }
    }
}

struct HighlightSwiftAdapter: CodeSyntaxHighlighter {
    @ObservedObject var cache = HLCache.shared

    func highlightCode(_ content: String, language: String?) -> Text {
        if let attr = cache.get(code: content, lang: language) {
            return Text(attr)
        } else {
            cache.ensure(code: content, lang: language)
            return Text(content) // 첫 프레임은 평문, 이후 version 증가로 리렌더됨
        }
    }
}
