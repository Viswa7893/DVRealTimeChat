//
//  UsersListView.swift
//  DVRealTimeChat
//
//  Created by Durga Viswanadh on 14/12/25.
//

import SwiftUI
import Combine

struct UsersListView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var appState: AppState
    @StateObject private var chatService: ChatService
    @State private var selectedUser: UserPublicResponse?
    @State private var isLoading = false
    @State private var showingChat = false
    @State private var selectedChatRoom: ChatRoomResponse?
    @State private var cancellables = Set<AnyCancellable>()
    
    // Track unread messages per chat room ID
    @State private var unreadCounts: [String: Int] = [:]
    
    init(authService: AuthService) {
        _chatService = StateObject(wrappedValue: ChatService(authService: authService))
    }
    
    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView()
                } else if chatService.users.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No users available")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    List(chatService.users) { user in
                        UserRow(
                            user: user,
                            unreadCount: getUnreadCount(for: user)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedUser = user
                            createChatAndNavigate(with: user)
                        }
                    }
                }
            }
            .navigationTitle("Users")
            .navigationBarItems(
                trailing: HStack(spacing: 16) {
                    // Connection status indicator
                    if appState.isWebSocketConnected {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Online")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    
                    // Refresh button
                    Button(action: {
                        Task {
                            await loadUsers()
                            await loadChatRooms()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    
                    // Logout button
                    Button(action: {
                        authService.logout()
                    }) {
                        Image(systemName: "arrow.right.square")
                    }
                }
            )
            .task {
                await loadUsers()
                await loadChatRooms()
                setupWebSocketListener()
            }
            .refreshable {
                await loadUsers()
                await loadChatRooms()
            }
            .sheet(isPresented: $showingChat) {
                if let chatRoom = selectedChatRoom,
                   let currentUser = authService.currentUser {
                    NavigationView {
                        ChatView(
                            viewModel: ChatViewModel(
                                webSocketManager: appState.webSocketManager,
                                currentUser: User(
                                    id: currentUser.id.uuidString,
                                    name: currentUser.name,
                                    avatarURL: currentUser.avatarURL,
                                    isOnline: true,
                                    isTyping: false
                                ),
                                chatRoom: ChatRoom(
                                    id: chatRoom.id.uuidString,
                                    name: chatRoom.name ?? getChatRoomName(for: chatRoom),
                                    participants: chatRoom.participants.map { p in
                                        User(
                                            id: p.id.uuidString,
                                            name: p.name,
                                            avatarURL: p.avatarURL,
                                            isOnline: p.isOnline,
                                            isTyping: false
                                        )
                                    },
                                    isGroup: chatRoom.isGroup
                                )
                            )
                        )
                        .navigationBarItems(trailing: Button("Done") {
                            showingChat = false
                            // Clear unread count when closing chat
                            if let roomId = selectedChatRoom?.id.uuidString {
                                unreadCounts[roomId] = 0
                            }
                        })
                    }
                }
            }
        }
    }
    
    private func loadUsers() async {
        isLoading = true
        do {
            try await chatService.fetchUsers()
            print("✅ Loaded \(chatService.users.count) users")
        } catch {
            print("❌ Failed to load users: \(error)")
        }
        isLoading = false
    }
    
    private func loadChatRooms() async {
        do {
            try await chatService.fetchChatRooms()
            print("✅ Loaded \(chatService.chatRooms.count) chat rooms")
        } catch {
            print("❌ Failed to load chat rooms: \(error)")
        }
    }
    
    private func setupWebSocketListener() {
        print("🔌 Setting up WebSocket listener for real-time updates")
        
        Task {
            for await event in await appState.webSocketManager.messagePublisher.values {
                await handleWebSocketEvent(event)
            }
        }
    }
    
    @MainActor
    private func handleWebSocketEvent(_ event: WebSocketEvent) async {
        switch event {
        case .userRegistered:
            print("👤 New user registered - refreshing list")
            await loadUsers()
            
        case .userStatusChanged(let userId, let isOnline):
            print("📊 User \(userId) status changed: \(isOnline ? "online" : "offline")")
            
            // Update the user's online status in the list
            if let index = chatService.users.firstIndex(where: { $0.id.uuidString == userId }) {
                let user = chatService.users[index]
                chatService.users[index] = UserPublicResponse(
                    id: user.id,
                    name: user.name,
                    avatarURL: user.avatarURL,
                    isOnline: isOnline
                )
                print("✅ Updated user \(user.name) online status to: \(isOnline)")
            }
            
        case .messageReceived(let message):
            // Only count as unread if:
            // 1. Message is not from current user
            // 2. Chat is not currently open
            guard let currentUserId = authService.currentUser?.id.uuidString else { return }
            
            if message.senderId != currentUserId {
                let roomId = message.chatRoomId
                
                // Only increment if this chat is NOT currently open
                let isChatOpen = (selectedChatRoom?.id.uuidString == roomId && showingChat)
                
                if !isChatOpen {
                    unreadCounts[roomId, default: 0] += 1
                    print("📬 New unread message in room \(roomId), count: \(unreadCounts[roomId] ?? 0)")
                }
            }
            
        default:
            break
        }
    }
    
    private func createChatAndNavigate(with user: UserPublicResponse) {
        Task {
            do {
                let chatRoom = try await chatService.createChatRoom(with: user.id)
                selectedChatRoom = chatRoom
                
                // Clear unread count when opening chat
                unreadCounts[chatRoom.id.uuidString] = 0
                
                showingChat = true
            } catch {
                print("❌ Failed to create chat room: \(error)")
            }
        }
    }
    
    private func getChatRoomName(for chatRoom: ChatRoomResponse) -> String {
        if let currentUserId = authService.currentUser?.id {
            let otherParticipant = chatRoom.participants.first { $0.id != currentUserId }
            return otherParticipant?.name ?? "Chat"
        }
        return "Chat"
    }
    
    private func getUnreadCount(for user: UserPublicResponse) -> Int {
        // Get chat room ID for this user
        if let chatRoomId = chatService.getChatRoomId(forUser: user.id) {
            return unreadCounts[chatRoomId.uuidString] ?? 0
        }
        return 0
    }
}

struct UserRow: View {
    let user: UserPublicResponse
    let unreadCount: Int
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(user.name.prefix(1).uppercased())
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    )
                
                // Online indicator - pulsing animation
                if user.isOnline {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                        )
                        .shadow(color: .green.opacity(0.5), radius: 2)
                }
            }
            
            // User info
            VStack(alignment: .leading, spacing: 4) {
                Text(user.name)
                    .font(.headline)
                
                Text(user.isOnline ? "Online" : "Offline")
                    .font(.caption)
                    .foregroundColor(user.isOnline ? .green : .secondary)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                // Unread badge
                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
