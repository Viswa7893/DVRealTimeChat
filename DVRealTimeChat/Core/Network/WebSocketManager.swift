//
//  WebSocketManager.swift
//  DVRealTimeChat
//
//  Created by Durga Viswanadh on 14/12/25.
//

import Foundation
import Combine

actor WebSocketManager {
    
    // MARK: - Configuration
    private struct Config {
        static let reconnectDelay: TimeInterval = 2.0
        static let maxReconnectDelay: TimeInterval = 30.0
        static let heartbeatInterval: TimeInterval = 30.0
        static let messageTimeout: TimeInterval = 10.0
        static let maxReconnectAttempts = 5
        static let authTimeout: TimeInterval = 5.0
    }
    
    // MARK: - Properties
    private var connectionState: ConnectionState = .disconnected
    private var webSocketTask: URLSessionWebSocketTask?
    private let urlSession: URLSession
    private let serverURL: URL
    
    private var reconnectAttempts = 0
    private var reconnectTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var isAuthenticated = false
    
    // Publishers - Use PassthroughSubject for events
    private let messageSubject = PassthroughSubject<WebSocketEvent, Never>()
    private let connectionStateSubject = CurrentValueSubject<ConnectionState, Never>(.disconnected)
    
    var messagePublisher: AnyPublisher<WebSocketEvent, Never> {
        messageSubject.eraseToAnyPublisher()
    }
    
    var connectionStatePublisher: AnyPublisher<ConnectionState, Never> {
        connectionStateSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    init(serverURL: URL) {
        self.serverURL = serverURL
        
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 30
        
        self.urlSession = URLSession(configuration: configuration)
    }
    
    // MARK: - Public Methods
    
    /// Connect to WebSocket server and authenticate
    func connect(authToken: String) async throws {
        // Make sure we're not already connected
        guard connectionStateSubject.value == .disconnected else {
            print("⚠️ Already connected or connecting")
            return
        }
        
        print("🔌 Starting WebSocket connection...")
        connectionStateSubject.send(.connecting)
        isAuthenticated = false
                
        // Create WebSocket task
        var request = URLRequest(url: serverURL)
        request.timeoutInterval = 30
        
        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()
        
        // Start listening for messages
        Task {
            await startListening()
        }
        
        // Wait a moment for connection to establish
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Send authentication message
        print("🔐 Sending authentication...")
        try await authenticate(token: authToken)
        
        // Wait for authentication confirmation
        let authResult = await waitForAuthentication()
        
        if authResult {
            print("✅ WebSocket authenticated successfully")
            connectionStateSubject.send(.connected)
            messageSubject.send(.connected)
            reconnectAttempts = 0
            
            // Start heartbeat only after successful authentication
            startHeartbeat()
        } else {
            print("❌ Authentication failed or timed out")
            await disconnect()
            throw WebSocketError.authenticationFailed
        }
    }
    
    /// Disconnect from WebSocket server
    func disconnect() async {
        print("📌 Disconnecting WebSocket...")
        
        isAuthenticated = false
        
        heartbeatTask?.cancel()
        heartbeatTask = nil
        
        reconnectTask?.cancel()
        reconnectTask = nil
        
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        
        if connectionState != .disconnected {
            connectionState = .disconnected
            connectionStateSubject.send(.disconnected)
            messageSubject.send(.disconnected)
        }
    }
    
    /// Send a message through WebSocket
    func send<T: Encodable>(_ message: T) async throws {
        guard isAuthenticated, let webSocketTask = webSocketTask else {
            print("❌ Cannot send: not authenticated")
            throw WebSocketError.notConnected
        }
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(message)
        let message = URLSessionWebSocketTask.Message.data(data)
        
        try await webSocketTask.send(message)
    }
    
    /// Send text message
    func sendText(_ text: String) async throws {
        guard isAuthenticated, let webSocketTask = webSocketTask else {
            print("❌ Cannot send: not authenticated")
            throw WebSocketError.notConnected
        }
        
        let message = URLSessionWebSocketTask.Message.string(text)
        try await webSocketTask.send(message)
    }
    
    // MARK: - Private Methods
    
    private func authenticate(token: String) async throws {
        let authMessage: [String: String] = [
            "type": "auth",
            "token": token
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: authMessage)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw WebSocketError.encodingFailed
        }
        
        guard let webSocketTask = webSocketTask else {
            throw WebSocketError.notConnected
        }
        
        let message = URLSessionWebSocketTask.Message.string(jsonString)
        try await webSocketTask.send(message)
    }
    
    private func waitForAuthentication() async -> Bool {
        let startTime = Date()
        
        while !isAuthenticated {
            // Check timeout
            if Date().timeIntervalSince(startTime) > Config.authTimeout {
                print("⏱️ Authentication timeout")
                return false
            }
            
            // Wait a bit before checking again
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        return true
    }
    
    private func startListening() async {
        guard let webSocketTask = webSocketTask else { return }
        
        do {
            let message = try await webSocketTask.receive()
            await handleMessage(message)
            
            // Continue listening recursively
            await startListening()
            
        } catch {
            await handleConnectionError(error)
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) async {
        switch message {
        case .string(let text):
            await processTextMessage(text)
            
        case .data(let data):
            await processDataMessage(data)
            
        @unknown default:
            print("⚠️ Unknown message type received")
        }
    }
    
    private func processTextMessage(_ text: String) async {
        print("📥 Received: \(text)")
        
        // Handle ping/pong
        if text == "ping" {
            try? await sendText("pong")
            return
        }
        
        if text == "pong" {
            print("💓 Pong received")
            return
        }
        
        // Handle plain text messages
        if !text.starts(with: "{") && !text.starts(with: "[") {
            print("📝 Plain text: \(text)")
            return
        }
        
        // Try to parse as JSON
        guard let data = text.data(using: .utf8) else {
            print("⚠️ Could not convert text to data")
            return
        }
        
        await processDataMessage(data)
    }

    private func processDataMessage(_ data: Data) async {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        // First check if it's valid JSON
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if let plainText = String(data: data, encoding: .utf8) {
                print("📝 Non-JSON text: \(plainText)")
            }
            return
        }
        
        // Check for "type" field
        guard let type = json["type"] as? String else {
            print("⚠️ JSON missing 'type' field")
            return
        }
        
        print("📨 Message type: \(type)")
        
        switch type {
        case "success":
            // Authentication successful
            if let message = json["message"] as? String,
               message.contains("Authenticated") {
                print("✅ Server confirmed authentication")
                isAuthenticated = true
            }
            
        case "message":
            if let messageData = try? JSONSerialization.data(withJSONObject: json),
               let message = try? decoder.decode(Message.self, from: messageData) {
                print("📬 Message from \(message.senderName): \(message.content)")
                messageSubject.send(.messageReceived(message))
            } else {
                print("⚠️ Failed to decode message")
            }
            
        case "typing":
            if let userId = json["userId"] as? String,
               let chatRoomId = json["chatRoomId"] as? String,
               let isTyping = json["isTyping"] as? Bool {
                messageSubject.send(.userTyping(userId: userId, chatRoomId: chatRoomId, isTyping: isTyping))
            }
            
        case "status", "userStatus":
            if let userId = json["userId"] as? String,
               let isOnline = json["isOnline"] as? Bool {
                messageSubject.send(.userStatusChanged(userId: userId, isOnline: isOnline))
            }
            
        case "userRegistered":
            // New user registered - trigger user list refresh
            print("👤 New user registered")
            messageSubject.send(.userRegistered)
            
        case "connected":
            print("✅ Server acknowledged connection")
            
        case "error":
            if let errorMessage = json["message"] as? String {
                print("❌ Server error: \(errorMessage)")
                messageSubject.send(.error(errorMessage))
            }
            
        default:
            print("⚠️ Unknown message type: \(type)")
        }
    }
    
    private func handleConnectionError(_ error: Error) async {
        print("❌ WebSocket error: \(error.localizedDescription)")
        
        isAuthenticated = false
        
        let nsError = error as NSError
        
        // Handle specific error codes
        if nsError.code == 57 { // Socket is not connected
            await attemptReconnect()
        } else {
            connectionState = .failed(error.localizedDescription)
            connectionStateSubject.send(.failed(error.localizedDescription))
            messageSubject.send(.error(error.localizedDescription))
            await attemptReconnect()
        }
    }
    
    private func attemptReconnect() async {
        guard reconnectAttempts < Config.maxReconnectAttempts else {
            connectionState = .failed("Max reconnect attempts reached")
            connectionStateSubject.send(.failed("Max reconnect attempts reached"))
            return
        }
        
        reconnectAttempts += 1
        connectionState = .reconnecting
        connectionStateSubject.send(.reconnecting)
        
        // Exponential backoff
        let delay = min(
            Config.reconnectDelay * pow(2.0, Double(reconnectAttempts - 1)),
            Config.maxReconnectDelay
        )
        
        print("🔄 Reconnecting in \(delay)s (attempt \(reconnectAttempts)/\(Config.maxReconnectAttempts))")
        
        // Note: Cannot auto-reconnect without auth token
        // The view must call connect(authToken:) again
    }
    
    private func startHeartbeat() {
        heartbeatTask?.cancel()
        
        heartbeatTask = Task {
            while !Task.isCancelled && isAuthenticated {
                try? await Task.sleep(nanoseconds: UInt64(Config.heartbeatInterval * 1_000_000_000))
                
                guard !Task.isCancelled, isAuthenticated else { break }
                
                do {
                    try await sendText("ping")
                    print("💓 Heartbeat sent")
                } catch {
                    print("❌ Heartbeat failed: \(error)")
                    await handleConnectionError(error)
                    break
                }
            }
        }
    }
}

// MARK: - WebSocketError
enum WebSocketError: LocalizedError {
    case notConnected
    case invalidURL
    case encodingFailed
    case decodingFailed
    case timeout
    case connectionClosed
    case authenticationFailed
    
    var errorDescription: String? {
        switch self {
        case .notConnected: return "WebSocket is not connected"
        case .invalidURL: return "Invalid WebSocket URL"
        case .encodingFailed: return "Failed to encode message"
        case .decodingFailed: return "Failed to decode message"
        case .timeout: return "Request timed out"
        case .connectionClosed: return "Connection closed unexpectedly"
        case .authenticationFailed: return "Authentication failed"
        }
    }
}
