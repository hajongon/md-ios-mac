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
    @Published var version: Int = 0

    private let highlighter = Highlight()

    private func key(for code: String, lang: String?, isDark: Bool) -> String {
        let themeKey = isDark ? "dark" : "light"
        return themeKey + "|" + (lang ?? "auto") + "#" + String(code.hashValue)
    }

    func get(code: String, lang: String?, isDark: Bool) -> AttributedString? {
        store[key(for: code, lang: lang, isDark: isDark)]
    }

    func ensure(code: String, lang: String?, isDark: Bool) {
        let k = key(for: code, lang: lang, isDark: isDark)
        guard store[k] == nil else { return }

        Task {
            do {
                // 💡 라이트/다크에 따라 HighlightSwift 색 테마 선택

                let raw: AttributedString
                if let lang, !lang.isEmpty {
                    raw = try await highlighter.attributedText(
                        code,
                        language: lang,
                        colors: isDark
                        ? .dark(.github)
                        : .light(.github)
                    )
                } else {
                    raw = try await highlighter.attributedText(
                        code,
                        colors: isDark
                        ? .dark(.github)
                        : .light(.github)
                    )
                }

                // 폰트 제거 → 폰트 크기는 Markdown 테마에서 통일
                var stripped = raw
                for run in stripped.runs {
                    stripped[run.range].font = nil
                }

                store[k] = stripped
                version &+= 1
            } catch {
                // 실패 시 캐시에 넣지 않음 → plain 렌더로 fallback
            }
        }
    }

    /// Markdown 문서 내의 코드블록들을 미리 하이라이트 캐싱
    func prewarm(markdown: String, isDark: Bool) {
        let pattern = #"```([\w+-]*)\n([\s\S]*?)```"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

        let range = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        let matches = regex.matches(in: markdown, range: range)

        for match in matches {
            let langRange = match.range(at: 1)
            let codeRange = match.range(at: 2)

            let lang = langRange.location != NSNotFound
                ? String(markdown[Range(langRange, in: markdown)!])
                : nil
            let code = codeRange.location != NSNotFound
                ? String(markdown[Range(codeRange, in: markdown)!])
                : ""

            ensure(code: code, lang: lang, isDark: isDark)
        }
    }
}

struct HighlightSwiftAdapter: CodeSyntaxHighlighter {
    @ObservedObject var cache = HLCache.shared
    let isDark: Bool

    init(isDark: Bool) {
        self.isDark = isDark
    }

    func highlightCode(_ content: String, language: String?) -> Text {
        if let attr = cache.get(code: content, lang: language, isDark: isDark) {
            return Text(attr)
        } else {
            cache.ensure(code: content, lang: language, isDark: isDark)
            return Text(content) // 최초엔 plain → 캐시 준비 후 리렌더
        }
    }
}
