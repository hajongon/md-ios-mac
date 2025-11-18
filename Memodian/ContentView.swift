//
//  ContentView.swift
//  Memodian
//
//  Created by hajongon on 11/5/25.
//

import Foundation
import SwiftUI

struct NoteRef: Identifiable, Hashable {
    let url: URL
    var id: String { url.path }
}

struct ContentView: View {
    @StateObject private var store = FileStore()
    @State private var selectedNote: NoteRef?
    @State private var text = ""
    @Environment(\.colorScheme) private var colorScheme   // ← 다크/라이트 전환을 위해 추가

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.notes) { item in
                    Button {
                        selectedNote = NoteRef(url: item.url)
                        text = (try? String(contentsOf: item.url, encoding: .utf8)) ?? ""
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title.isEmpty ? "Untitled" : item.title)
                                .font(.system(size: 14))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .lineLimit(1)
                            Text(item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 10))
                                .foregroundColor(.gray)
                                // .foregroundStyle(.secondary)
                        }
                    }
                    // ✅ 왼쪽 스와이프 시 우측 끝에 휴지통 아이콘 노출
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            store.delete(item.url)
                            // 열려 있던 시트를 그 메모가 쓰고 있었다면 같이 정리
                            if selectedNote?.url == item.url {
                                selectedNote = nil
                                text = ""
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .tint(.gray)
                    }
                }
                // (선택) 편집 모드에서의 삭제 제스처도 계속 살려두고 싶다면 유지
                .onDelete { idx in
                    idx.map { store.notes[$0].url }.forEach(store.delete)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let url = store.createNote() {
                            selectedNote = NoteRef(url: url)
                            text = ""
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fullScreenCover(item: $selectedNote) { noteRef in
                NavigationStack {
                    EditorView(text: $text, originalURL: noteRef.url) {
                        store.save(text, to: noteRef.url)
                        selectedNote = nil
                    }
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }
}
