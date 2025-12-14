//
//  ContentView.swift
//  DVRealTimeChat
//
//  Created by Durga Viswanadh on 14/12/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Group {
            if appState.authService.isAuthenticated {
                UsersListView(authService: appState.authService)
                    .environmentObject(appState.authService)
                    .onAppear {
                        print("🟢 ContentView: Showing UsersListView (authenticated)")
                    }
            } else {
                LoginView()
                    .environmentObject(appState.authService)
                    .onAppear {
                        print("🔴 ContentView: Showing LoginView (not authenticated)")
                    }
            }
        }
        .onChange(of: appState.authService.isAuthenticated) { newValue in
            print("🔄 ContentView: Auth state changed to: \(newValue)")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
