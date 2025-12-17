//
//  ChatService.swift
//  DVRealTimeChat
//
//  Created by Durga Viswanadh on 14/12/25.
//

import Foundation
import Combine

@MainActor
class ChatService: ObservableObject {
    @Published var users: [UserPublicResponse] = []
    @Published var chatRooms: [ChatRoomResponse] = []
    
    // Map user ID to chat room ID for quick lookup
    private var userToChatRoomMap: [UUID: UUID] = [:]
    
    private let baseURL = "http://127.0.0.1:8080/api"
    private let authService: AuthService
    
    // Shared JSON Decoder with proper configuration
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    
    init(authService: AuthService) {
        self.authService = authService
    }
    
    // MARK: - Users
    func fetchUsers() async throws {
        guard let token = authService.authToken else {
            throw ChatError.notAuthenticated
        }
        
        let url = URL(string: "\(baseURL)/users")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        // Debug print
        if let jsonString = String(data: data, encoding: .utf8) {
            print("📥 Users response: \(jsonString)")
        }
        
        self.users = try decoder.decode([UserPublicResponse].self, from: data)
    }
    
    // MARK: - Chat Rooms
    func fetchChatRooms() async throws {
        guard let token = authService.authToken else {
            throw ChatError.notAuthenticated
        }
        
        let url = URL(string: "\(baseURL)/chat-rooms")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        self.chatRooms = try decoder.decode([ChatRoomResponse].self, from: data)
        
        // Build user-to-chatroom mapping
        buildUserToChatRoomMap()
    }
    
    func createChatRoom(with userId: UUID) async throws -> ChatRoomResponse {
        guard let token = authService.authToken else {
            throw ChatError.notAuthenticated
        }
        
        let url = URL(string: "\(baseURL)/chat-rooms")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = ["participantId": userId.uuidString]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let chatRoom = try decoder.decode(ChatRoomResponse.self, from: data)
        
        // Add to our local list
        chatRooms.append(chatRoom)
        
        // Update mapping
        buildUserToChatRoomMap()
        
        return chatRoom
    }
    
    // MARK: - Messages
    func fetchMessages(for chatRoomId: UUID) async throws -> [MessageResponse] {
        guard let token = authService.authToken else {
            throw ChatError.notAuthenticated
        }
        
        let url = URL(string: "\(baseURL)/chat-rooms/\(chatRoomId.uuidString)/messages")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try decoder.decode([MessageResponse].self, from: data)
    }
    
    // MARK: - Helper Methods
    
    /// Get chat room ID for a specific user (for 1-on-1 chats)
    func getChatRoomId(forUser userId: UUID) -> UUID? {
        return userToChatRoomMap[userId]
    }
    
    /// Build mapping of user IDs to chat room IDs for quick lookup
    private func buildUserToChatRoomMap() {
        guard let currentUserId = authService.currentUser?.id else { return }
        
        userToChatRoomMap.removeAll()
        
        for chatRoom in chatRooms where !chatRoom.isGroup {
            // For 1-on-1 chats, find the other participant
            if let otherUser = chatRoom.participants.first(where: { $0.id != currentUserId }) {
                userToChatRoomMap[otherUser.id] = chatRoom.id
            }
        }
        
        print("📊 Built user-to-chatroom map: \(userToChatRoomMap.count) mappings")
    }
}

// MARK: - Models
struct UserPublicResponse: Codable, Identifiable {
    let id: UUID
    let name: String
    let avatarURL: String?
    var isOnline: Bool  // Changed to var for updating
    
    var stringId: String {
        id.uuidString
    }
}

struct ChatRoomResponse: Codable, Identifiable {
    let id: UUID
    let name: String?
    let isGroup: Bool
    let participants: [UserPublicResponse]
    let lastMessage: MessageResponse?
    let unreadCount: Int?
    
    var stringId: String {
        id.uuidString
    }
}

struct MessageResponse: Codable, Identifiable {
    let id: UUID
    let content: String
    let senderId: UUID
    let senderName: String
    let chatRoomId: UUID
    let timestamp: Date
    
    var stringId: String {
        id.uuidString
    }
}

enum ChatError: LocalizedError {
    case notAuthenticated
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated"
        case .invalidResponse:
            return "Invalid server response"
        }
    }
}
