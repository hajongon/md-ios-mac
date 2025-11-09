//
//  FileStore.swift
//  Memodian
//
//  Created by hajongon on 11/5/25.
//

import Foundation

struct NoteItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let title: String
    let updatedAt: Date
}

final class FileStore: NSObject, ObservableObject, NSFilePresenter {
    @Published var notes: [NoteItem] = []
    private let notesDir: URL

    var presentedItemURL: URL? { notesDir }
    var presentedItemOperationQueue: OperationQueue = .main

    override init() {
        let fm = FileManager.default

        // iCloud 컨테이너 시도
        if let base = fm.url(forUbiquityContainerIdentifier: "iCloud.com.hajongon.Memodian") {
            print("✅ iCloud container found:", base.path)
            let icloudNotes = base.appendingPathComponent("Documents/notes", isDirectory: true)
            try? fm.createDirectory(at: icloudNotes, withIntermediateDirectories: true)
            notesDir = icloudNotes
            print("notesDir:", notesDir.path)
        } else {
            // 폴백: 로컬 Documents
            print("⚠️ iCloud container not available, using local documents.")
            let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
            let localNotes = docs.appendingPathComponent("notes", isDirectory: true)
            try? fm.createDirectory(at: localNotes, withIntermediateDirectories: true)
            notesDir = localNotes
        }

        super.init() // ✅ 먼저 상위 클래스 초기화

        // iCloud 파일 변경 감시 등록
        NSFileCoordinator.addFilePresenter(self)

        loadNotes() // ✅ 이제 안전하게 self 사용 가능
    }
    
    func presentedSubitemDidChange(at url: URL) {
        print("🔄 iCloud 파일 변경 감지:", url.lastPathComponent)
        DispatchQueue.main.async {
            self.loadNotes()
        }
    }

    func loadNotes() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: notesDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let items: [NoteItem] = urls
            .filter { $0.pathExtension.lowercased() == "md" }
            .map { url in
                let rv = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                let updated = rv?.contentModificationDate ?? .distantPast
                let rawTitle = (try? firstLine(of: url))?.trimmingCharacters(in: .whitespacesAndNewlines)
                let title = (rawTitle != nil && !rawTitle!.isEmpty) ? rawTitle! : "Untitled"
                return NoteItem(url: url, title: title, updatedAt: updated)
            }
            .sorted { $0.updatedAt > $1.updatedAt }


        self.notes = items
    }

    func createNote() -> URL? {
        let name = "note-\(Int(Date().timeIntervalSince1970)).md"
        let url = notesDir.appendingPathComponent(name)
        do {
            try "# New Note\n\n".write(to: url, atomically: true, encoding: .utf8)
            loadNotes()
            return url
        } catch {
            print("Create note error:", error)
            return nil
        }
    }

    func save(_ text: String, to url: URL) {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            loadNotes() // 저장 후 리스트 즉시 갱신(제목도 갱신)
        } catch {
            print("Save error:", error)
        }
    }

    func delete(_ noteURL: URL) {
        do {
            try FileManager.default.removeItem(at: noteURL)
            loadNotes()
        } catch {
            print("Delete error:", error)
        }
    }
}

// MARK: - Helpers
private func firstLine(of url: URL) throws -> String {
    // 파일 전체를 읽지 않고 첫 줄만 빠르게 가져오는 간단한 구현
    // (현재 크기 작으니 그대로 읽어도 무방하지만 확장성 고려)
    let text = try String(contentsOf: url, encoding: .utf8)
    if let newlineIdx = text.firstIndex(of: "\n") {
        return String(text[..<newlineIdx])
    } else {
        return text
    }
}
