//
//  HighlightSwiftAdapter.swift
//  Memodian
//
//  Created by hajongon on 11/9/25.
//

// HighlightSwiftAdapter.swift
import SwiftUI
import MarkdownUI
import HighlightSwift

@MainActor
final class HLCache: ObservableObject {
    static let shared = HLCache()
    @Published var store: [String: AttributedString] = [:]
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
                    // 언어 명시: README 시그니처 그대로
                    attr = try await highlighter.attributedText(code, language: lang)
                } else {
                    // 자동 감지
                    attr = try await highlighter.attributedText(code)
                }
                store[k] = attr
            } catch {
                // 실패 시 plain 유지
            }
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
            return Text(content)
        }
    }
}
