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
            } else {
                LoginView()
                    .environmentObject(appState.authService)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
