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
                                .font(.headline)
                                .lineLimit(1)
                            Text(item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { idx in
                    idx.map { store.notes[$0].url }.forEach(store.delete)
                }
            }
            .navigationTitle("Notes")
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
            .sheet(item: $selectedNote) { noteRef in
                NavigationStack {
                    EditorView(
                        text: $text,
                        originalURL: noteRef.url
                    ) {
                        store.save(text, to: noteRef.url)
                        selectedNote = nil
                    }
                    .navigationBarTitleDisplayMode(.inline) // 선택 사항: 타이틀 높이 줄이기
                }
            }

        }
    }
}
