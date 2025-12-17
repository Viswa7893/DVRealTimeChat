//
//  DVRealTimeChatApp.swift
//  DVRealTimeChat
//
//  Created by Durga Viswanadh on 14/12/25.
//

import SwiftUI

@main
struct DVRealTimeChatApp: App {
    @StateObject private var appState = AppState()
    
    init() {
        print("🚀 App Starting - Version 1.0.1")
        print("🚀 AppState will be initialized next...")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(appState.colorScheme)
        }
    }
}
