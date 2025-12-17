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
    @Published var connectionError: String?
    
    // MARK: - Properties
    private let webSocketManager: WebSocketManager  // Global WebSocket - already connected
    private let currentUser: User
    private let chatRoom: ChatRoom
    private var cancellables = Set<AnyCancellable>()
    private var typingTimer: Timer?
    
    // Track message send state
    private var pendingMessages: [String: Message] = [:]
    
    // Auth token for API calls
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
        
        // Load message history on init
        Task {
            await loadMessageHistory()
        }
    }
    
    // Expose only the current user's id for view access
    var currentUserID: String { currentUser.id }
    
    // MARK: - Setup
    private func setupSubscriptions() {
        // Subscribe to WebSocket messages (global WebSocket is already connected)
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
    
    /// Load message history from server when chat opens
    func loadMessageHistory() async {
        do {
            guard let token = authToken else { return }
            
            let url = URL(string: "http://127.0.0.1:8080/api/chat-rooms/\(chatRoom.id)/messages")!
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, _) = try await URLSession.shared.data(for: request)
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601
            
            let messageDTOs = try decoder.decode([MessageDTO].self, from: data)
            
            // Convert to local Message models
            let historyMessages = messageDTOs.map { dto in
                Message(
                    id: dto.id.uuidString,
                    senderId: dto.senderId.uuidString,
                    senderName: dto.senderName,
                    content: dto.content,
                    timestamp: dto.timestamp,
                    chatRoomId: dto.chatRoomId.uuidString,
                    deliveryState: .delivered
                )
            }
            
            self.messages = historyMessages
            print("✅ Loaded \(historyMessages.count) messages from history")
            
        } catch {
            print("❌ Failed to load message history: \(error)")
        }
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
        
        // Send to server via global WebSocket
        Task {
            do {
                let messageDTO: [String: Any] = [
                    "type": "message",
                    "content": message.content,
                    "chatRoomId": message.chatRoomId
                ]
                
                let jsonData = try JSONSerialization.data(withJSONObject: messageDTO)
                let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
                
                print("📤 Sending message: \(message.content)")
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
                print("⚠️ Failed to send typing indicator: \(error)")
            }
        }
    }
    
    func handleTextFieldChange() {
        // Cancel existing timer
        typingTimer?.invalidate()

        if !messageText.isEmpty {
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
            print("📬 Received message for room \(message.chatRoomId)")
            
            // Only add message if it's for this chat room
            guard message.chatRoomId == chatRoom.id else {
                print("⚠️ Message not for this room (this: \(chatRoom.id), msg: \(message.chatRoomId))")
                return
            }
            
            // Don't add if it's our own message (already added optimistically)
            if message.senderId != currentUser.id {
                var mutableMessage = message
                mutableMessage.deliveryState = .delivered
                messages.append(mutableMessage)
                print("✅ Added message from \(message.senderName)")
            } else {
                // Our own message came back - mark as delivered
                if let index = messages.firstIndex(where: { $0.id == message.id }) {
                    messages[index].deliveryState = .delivered
                    print("✅ Our message delivered")
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
            connectionError = message
            
        case .connected:
            print("✅ ChatViewModel: WebSocket is connected")
            
        case .disconnected:
            print("🔌 ChatViewModel: WebSocket disconnected")
            
        case .userRegistered:
            break
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

// MARK: - DTO for API calls
extension ChatViewModel {
    struct MessageDTO: Codable {
        let id: UUID
        let content: String
        let senderId: UUID
        let senderName: String
        let chatRoomId: UUID
        let timestamp: Date
    }
}
