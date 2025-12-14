//
//  ChatView.swift
//  DVRealTimeChat
//
//  Created by Durga Viswanadh on 14/12/25.
//


import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @State private var scrollProxy: ScrollViewProxy?
    @Namespace private var bottomID
    
    init(viewModel: ChatViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Connection status bar
            ConnectionStatusView(state: viewModel.connectionState)
            
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(
                                message: message,
                                isCurrentUser: viewModel.isMessageFromCurrentUser(message),
                                onRetry: {
                                    viewModel.retryMessage(message.id)
                                }
                            )
                            .id(message.id)
                            .transition(.scale.combined(with: .opacity))
                        }
                        
                        // Typing indicator
                        if !viewModel.typingUsers.isEmpty {
                            TypingIndicatorView()
                                .transition(.scale.combined(with: .opacity))
                        }
                        
                        // Bottom anchor
                        Color.clear
                            .frame(height: 1)
                            .id(bottomID)
                    }
                    .padding()
                }
                .onAppear {
                    scrollProxy = proxy
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: viewModel.messages.count) { _ in
                    withAnimation(.easeOut(duration: 0.3)) {
                        scrollToBottom(proxy: proxy)
                    }
                }
            }
            
            // Input
            MessageInputView(
                text: $viewModel.messageText,
                onSend: viewModel.sendMessage,
                onChange: viewModel.handleTextFieldChange
            )
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.connect()
        }
        .onDisappear {
            viewModel.disconnect()
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        proxy.scrollTo(bottomID, anchor: .bottom)
    }
}
