//
//  CacheManager.swift
//  Memodian
//
//  Created by hajongon on 11/6/25.
//

import Foundation

// 충돌 처리 정책
enum CommitPolicy {
    case originalWins   // 원본 유지, 캐시는 "conflict copy"로 저장
    case cacheWins      // 캐시로 원본 교체, 기존 원본은 백업 이름으로 이동
}

struct NoteSessionMeta: Codable {
    let originalURL: URL           // iCloud 원본
    let cacheURL: URL              // 로컬 캐시(편집용)
    let openedAt: Date
    let originalFingerprint: String
    var lastSavedAt: Date?
}

final class CacheManager {
    static let shared = CacheManager()
    private init() {}

    // MARK: - 경로
    private func cacheDir() throws -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Editing", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - 지문(버전)
    func fingerprint(for url: URL) -> String {
        let rv = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let ts = rv?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let size = rv?.fileSize ?? 0
        return "\(ts)#\(size)"
    }

    // MARK: - 세션 시작
    func beginEditing(original: URL) throws -> NoteSessionMeta {
        let dir = try cacheDir()
        let cache = dir.appendingPathComponent(UUID().uuidString + ".md.session")
        // 원본이 없을 수도 있으니 없으면 빈 파일로 시작
        if FileManager.default.fileExists(atPath: original.path) {
            try? FileManager.default.removeItem(at: cache)
            try FileManager.default.copyItem(at: original, to: cache)
        } else {
            try "# New Note\n\n".write(to: cache, atomically: true, encoding: .utf8)
        }

        let meta = NoteSessionMeta(
            originalURL: original,
            cacheURL: cache,
            openedAt: Date(),
            originalFingerprint: fingerprint(for: original),
            lastSavedAt: nil
        )
        return meta
    }

    // MARK: - 캐시에만 자동 저장
    func autosave(text: String, to cache: URL) {
        try? text.write(to: cache, atomically: true, encoding: .utf8)
    }

    // MARK: - 커밋(저장 종료 시 iCloud 반영)
    func commit(_ meta: NoteSessionMeta, policy: CommitPolicy = .originalWins) throws {
        // 1) 캐시/원본 내용 비교
        let cacheText = (try? String(contentsOf: meta.cacheURL, encoding: .utf8)) ?? ""
        let originalText = (try? String(contentsOf: meta.originalURL, encoding: .utf8)) ?? ""

        // ✅ 내용이 완전히 동일하면: 아무것도 쓰지 않고 종료
        if cacheText == originalText {
            print("✅ commit: 내용 동일 → 원본 미변경, 캐시만 삭제")
            try? FileManager.default.removeItem(at: meta.cacheURL)
            return
        }

        // 2) 여기까지 왔다는 건 내용이 실제로 바뀌었다는 뜻
        let currentFP = fingerprint(for: meta.originalURL)

        switch (currentFP == meta.originalFingerprint, policy) {
        case (true, _):
            // 충돌 없음 → 원자적 교체
            try coordinatedReplace(target: meta.originalURL, with: cacheText)

        case (false, .originalWins):
            // 충돌 → 원본 유지, 캐시를 conflict copy로 보존
            let parent = meta.originalURL.deletingLastPathComponent()
            let base = meta.originalURL.deletingPathExtension().lastPathComponent
            let stamp = Date().formatted(date: .numeric, time: .standard)
                .replacingOccurrences(of: ":", with: "-")
            let conflict = parent.appendingPathComponent("\(base) (conflict \(stamp)).md")
            try cacheText.write(to: conflict, atomically: true, encoding: .utf8)

        case (false, .cacheWins):
            // 충돌 → 원본 백업 후 캐시로 교체
            let parent = meta.originalURL.deletingLastPathComponent()
            let base = meta.originalURL.deletingPathExtension().lastPathComponent
            let stamp = Date().formatted(date: .numeric, time: .standard)
                .replacingOccurrences(of: ":", with: "-")
            let backup = parent.appendingPathComponent("\(base) (backup \(stamp)).md")
            try? FileManager.default.moveItem(at: meta.originalURL, to: backup)
            try coordinatedReplace(target: meta.originalURL, with: cacheText)
        }

        // 3) 캐시 정리
        try? FileManager.default.removeItem(at: meta.cacheURL)
    }


    private func coordinatedReplace(target: URL, with text: String) throws {
        let coord = NSFileCoordinator(filePresenter: nil)
        var err: NSError?
        coord.coordinate(writingItemAt: target, options: .forReplacing, error: &err) { url in
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
        if let err { throw err }
    }
}
