//
//  HighlightSwiftAdapter.swift
//  Memodian
//
//  Created by hajongon on 11/9/25.
//



// 파일: HighlightSwiftAdapter.swift

import SwiftUI
import MarkdownUI
import HighlightSwift

@MainActor
final class HLCache: ObservableObject {
    static let shared = HLCache()
    @Published var store: [String: AttributedString] = [:]
    @Published var version: Int = 0                  // ✅ 프리뷰 리렌더 트리거용
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
                let raw: AttributedString
                if let lang, !lang.isEmpty {
                    raw = try await highlighter.attributedText(code, language: lang)
                } else {
                    raw = try await highlighter.attributedText(code)
                }
                // ✅ 폰트 제거: 크기는 바깥(MarkdownTextStyle)이 책임지도록
                var stripped = raw
                for run in stripped.runs {
                    stripped[run.range].font = nil
                }
                store[k] = stripped
                version &+= 1                           // ✅ 구독자에게 변경 알림
            } catch {
                // 실패 시 캐시에 넣지 않음(plain 렌더로 fallback)
            }
        }
    }
}

struct HighlightSwiftAdapter: CodeSyntaxHighlighter {
    @ObservedObject var cache = HLCache.shared

    func highlightCode(_ content: String, language: String?) -> Text {
        if let attr = cache.get(code: content, lang: language) {
            return Text(attr)                          // ✅ 폰트 없는 AttributedString (색상 등만 유지)
        } else {
            cache.ensure(code: content, lang: language)
            return Text(content)                       // 최초엔 plain → 캐시 준비되면 다시 렌더
        }
    }
}

extension HLCache {
    /// Markdown 문서 내의 코드블록들을 미리 하이라이트 캐싱
    func prewarm(markdown: String) {
        // ```lang ... ``` 형태의 코드 블록들을 정규식으로 추출
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

            ensure(code: code, lang: lang)
        }
    }
}

