//
//  MemodianApp.swift
//  Memodian
//
//  Created by hajongon on 11/5/25.
//

import SwiftUI

@main
struct MemodianApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
        .preferredColorScheme(.light) // ✅ View에 붙이기 (WindowGroup이 아님)
      // 필요하면: .environment(\.colorScheme, .light) 도 추가 가능
    }
  }
}
