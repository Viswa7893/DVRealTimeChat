//
//  ChatViewModel.swift
//  DVRealTimeChat
//
//  Created by Durga Viswanadh on 14/12/25.
//

import Foundation
import Combine
import SwiftUI

@MainActor
class ChatViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published private(set) var messages: [Message] = []
    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var typingUsers: Set<String> = []
    @Published private(set) var onlineUsers: Set<String> = []
    @Published var messageText: String = ""
    
    // MARK: - Properties
    private let webSocketManager: WebSocketManager
    private let currentUser: User
    private let chatRoom: ChatRoom
    private var cancellables = Set<AnyCancellable>()
    private var typingTimer: Timer?
    
    // Track message send state
    private var pendingMessages: [String: Message] = [:]
    
    // Auth token for WebSocket
    private var authToken: String?
    
    // MARK: - Initialization
    init(
        webSocketManager: WebSocketManager,
        currentUser: User,
        chatRoom: ChatRoom,
        authToken: String? = nil
    ) {
        self.webSocketManager = webSocketManager
        self.currentUser = currentUser
        self.chatRoom = chatRoom
        self.authToken = authToken ?? UserDefaults.standard.string(forKey: "auth_token")
        
        setupSubscriptions()
    }
    
    // Expose only the current user's id for view access
    var currentUserID: String { currentUser.id }
    
    // MARK: - Setup
    private func setupSubscriptions() {
        // Subscribe to WebSocket messages
        Task {
            for await event in await webSocketManager.messagePublisher.values {
                await handleWebSocketEvent(event)
            }
        }
        
        // Subscribe to connection state
        Task {
            for await state in await webSocketManager.connectionStatePublisher.values {
                self.connectionState = state
            }
        }
    }
    
    // MARK: - Public Methods
    
    func connect() {
        Task {
            await webSocketManager.connect()
            
            // Authenticate after connection
            if let token = authToken {
                try? await authenticateWebSocket(token: token)
            }
        }
    }
    
    func disconnect() {
        Task {
            await webSocketManager.disconnect()
        }
    }
    
    private func authenticateWebSocket(token: String) async throws {
        let authMessage: [String: String] = [
            "type": "auth",
            "token": token
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: authMessage)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
        
        try await webSocketManager.sendText(jsonString)
    }
    
    func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        let message = Message(
            id: UUID().uuidString,
            senderId: currentUser.id,
            senderName: currentUser.name,
            content: messageText,
            timestamp: Date(),
            chatRoomId: chatRoom.id,
            deliveryState: .sending
        )
        
        // Add to local messages immediately (optimistic update)
        messages.append(message)
        pendingMessages[message.id] = message
        
        // Clear input
        messageText = ""
        
        // Send to server
        Task {
            do {
                // Create a DTO for sending
                let messageDTO: [String: Any] = [
                    "type": "message",
                    "content": message.content,
                    "chatRoomId": message.chatRoomId
                ]
                
                let jsonData = try JSONSerialization.data(withJSONObject: messageDTO)
                let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
                
                try await webSocketManager.sendText(jsonString)
                
                // Update delivery state
                updateMessageDeliveryState(messageId: message.id, state: .sent)
                
            } catch {
                print("❌ Failed to send message: \(error)")
                updateMessageDeliveryState(messageId: message.id, state: .failed(error))
            }
        }
    }
    
    func sendTypingIndicator(isTyping: Bool) {
        Task {
            let typingDTO: [String: Any] = [
                "type": "typing",
                "chatRoomId": chatRoom.id,
                "isTyping": isTyping
            ]
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: typingDTO)
                let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
                try await webSocketManager.sendText(jsonString)
            } catch {
                print("❌ Failed to send typing indicator: \(error)")
            }
        }
    }
    
    func handleTextFieldChange() {
        // Cancel existing timer
        typingTimer?.invalidate()

        if !messageText.isEmpty {
            // Send typing indicator on the main actor
            Task { @MainActor in
                self.sendTypingIndicator(isTyping: true)
            }

            // Stop typing after 2 seconds of inactivity
            typingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    self.sendTypingIndicator(isTyping: false)
                }
            }
            // Ensure timer is scheduled on the main run loop
            RunLoop.main.add(typingTimer!, forMode: .common)
        } else {
            Task { @MainActor in
                self.sendTypingIndicator(isTyping: false)
            }
        }
    }
    
    func retryMessage(_ messageId: String) {
        guard let message = messages.first(where: { $0.id == messageId }) else {
            return
        }
        
        // Update state to sending
        updateMessageDeliveryState(messageId: messageId, state: .sending)
        
        // Retry send
        Task {
            do {
                let messageDTO: [String: Any] = [
                    "type": "message",
                    "content": message.content,
                    "chatRoomId": message.chatRoomId
                ]
                
                let jsonData = try JSONSerialization.data(withJSONObject: messageDTO)
                let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
                
                try await webSocketManager.sendText(jsonString)
                updateMessageDeliveryState(messageId: messageId, state: .sent)
                
            } catch {
                updateMessageDeliveryState(messageId: messageId, state: .failed(error))
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func handleWebSocketEvent(_ event: WebSocketEvent) async {
        switch event {
        case .messageReceived(let message):
            // Only add message if it's for this chat room
            guard message.chatRoomId == chatRoom.id else { return }
            
            // Don't add if it's our own message (already added optimistically)
            if message.senderId != currentUser.id {
                var mutableMessage = message
                mutableMessage.deliveryState = .delivered
                messages.append(mutableMessage)
            } else {
                // Our own message came back - mark as delivered
                if let index = messages.firstIndex(where: { $0.id == message.id }) {
                    messages[index].deliveryState = .delivered
                }
            }
            
        case .messageSent(let messageId):
            updateMessageDeliveryState(messageId: messageId, state: .delivered)
            
        case .userTyping(let userId, let chatRoomId, let isTyping):
            guard chatRoomId == self.chatRoom.id, userId != currentUser.id else { return }
            
            if isTyping {
                typingUsers.insert(userId)
            } else {
                typingUsers.remove(userId)
            }
            
        case .userStatusChanged(let userId, let isOnline):
            if isOnline {
                onlineUsers.insert(userId)
            } else {
                onlineUsers.remove(userId)
            }
            
        case .error(let message):
            print("❌ WebSocket error: \(message)")
            
        case .connected:
            print("✅ Connected to chat")
            
        case .disconnected:
            print("🔌 Disconnected from chat")
        }
    }
    
    private func updateMessageDeliveryState(messageId: String, state: DeliveryState) {
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            messages[index].deliveryState = state
        }
        
        // Remove from pending if delivered or failed
        if case .delivered = state {
            pendingMessages.removeValue(forKey: messageId)
        } else if case .failed = state {
            pendingMessages.removeValue(forKey: messageId)
        }
    }
    
    func isMessageFromCurrentUser(_ message: Message) -> Bool {
        message.senderId == currentUser.id
    }
}
