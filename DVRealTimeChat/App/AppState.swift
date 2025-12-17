//
//  AppState.swift
//  DVRealTimeChat
//
//  Created by Durga Viswanadh on 14/12/25.
//

import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var colorScheme: ColorScheme? = nil
    @Published var isAuthenticated = false
    @Published var isWebSocketConnected = false
    
    let authService = AuthService()
    private var cancellables = Set<AnyCancellable>()
    
    // Singleton WebSocketManager
    lazy var webSocketManager: WebSocketManager = {
        let url = URL(string: "ws://127.0.0.1:8080/ws")!
        return WebSocketManager(serverURL: url)
    }()
    
    init() {
        print("🎯 AppState: Initializing")
        
        // Mirror authService.isAuthenticated to our own @Published property
        authService.$isAuthenticated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newValue in
                print("🔔 AppState: isAuthenticated changed to \(newValue)")
                self?.isAuthenticated = newValue
                
                // Connect/disconnect WebSocket based on auth state
                if newValue {
                    self?.connectWebSocket()
                } else {
                    self?.disconnectWebSocket()
                }
            }
            .store(in: &cancellables)
        
        // Monitor WebSocket connection state
        Task {
            for await state in await webSocketManager.connectionStatePublisher.values {
                self.isWebSocketConnected = (state == .connected)
                print("🔌 WebSocket state: \(state.displayText)")
            }
        }
        
        print("🎯 AppState: Initialization complete")
    }
    
    private func connectWebSocket() {
        guard let token = authService.authToken else {
            print("⚠️ Cannot connect WebSocket: no auth token")
            return
        }
        
        print("🔌 AppState: Connecting global WebSocket...")
        
        Task {
            do {
                try await webSocketManager.connect(authToken: token)
                print("✅ AppState: Global WebSocket connected")
            } catch {
                print("❌ AppState: Failed to connect WebSocket - \(error)")
            }
        }
    }
    
    private func disconnectWebSocket() {
        print("📌 AppState: Disconnecting global WebSocket...")
        
        Task {
            await webSocketManager.disconnect()
            print("✅ AppState: Global WebSocket disconnected")
        }
    }
}
