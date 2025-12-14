//
//  UsersListView.swift
//  DVRealTimeChat
//
//  Created by Durga Viswanadh on 14/12/25.
//

import SwiftUI

struct UsersListView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var appState: AppState
    @StateObject private var chatService: ChatService
    @State private var selectedUser: UserPublicResponse?
    @State private var isLoading = false
    @State private var showingChat = false
    @State private var selectedChatRoom: ChatRoomResponse?
    
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
                        UserRow(user: user)
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
                trailing: Button(action: { authService.logout() }) {
                    Image(systemName: "arrow.right.square")
                }
            )
            .task {
                await loadUsers()
            }
            .refreshable {
                await loadUsers()
            }
            .sheet(isPresented: $showingChat) {
                if let chatRoom = selectedChatRoom,
                   let currentUser = authService.currentUser {
                    NavigationView {
                        ChatView(
                            viewModel: ChatViewModel(
                                webSocketManager: appState.webSocketManager,
                                currentUser: User(
                                    id: currentUser.id.uuidString,  // Convert UUID to String
                                    name: currentUser.name,
                                    avatarURL: currentUser.avatarURL,
                                    isOnline: true,
                                    isTyping: false
                                ),
                                chatRoom: ChatRoom(
                                    id: chatRoom.id.uuidString,  // Convert UUID to String
                                    name: chatRoom.name ?? getChatRoomName(for: chatRoom),
                                    participants: chatRoom.participants.map { p in
                                        User(
                                            id: p.id.uuidString,  // Convert UUID to String
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
        } catch {
            print("❌ Failed to load users: \(error)")
        }
        isLoading = false
    }
    
    private func createChatAndNavigate(with user: UserPublicResponse) {
        Task {
            do {
                let chatRoom = try await chatService.createChatRoom(with: user.id)  // Changed to user.id (UUID)
                selectedChatRoom = chatRoom
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
}

struct UserRow: View {
    let user: UserPublicResponse
    
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
                
                // Online indicator
                if user.isOnline {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                        )
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
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
