//
//  AppState.swift
//  DVRealTimeChat
//
//  Created by Durga Viswanadh on 14/12/25.
//

import SwiftUI
import Combine

class AppState: ObservableObject {
    @Published var colorScheme: ColorScheme? = nil
    @Published var authService = AuthService()
    
    // Singleton WebSocketManager
    lazy var webSocketManager: WebSocketManager = {
        let url = URL(string: "ws://127.0.0.1:8080/ws")!
        return WebSocketManager(serverURL: url)
    }()
}
