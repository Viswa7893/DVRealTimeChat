//
//  MessageBubble.swift
//  DVRealTimeChat
//
//  Created by Durga Viswanadh on 14/12/25.
//

import SwiftUI

struct MessageBubble: View {
    let message: Message
    let isCurrentUser: Bool
    let onRetry: () -> Void
    
    var body: some View {
        HStack {
            if isCurrentUser { Spacer() }
            
            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                // Sender name (only for other users)
                if !isCurrentUser {
                    Text(message.senderName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Message bubble
                HStack(spacing: 8) {
                    Text(message.content)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(bubbleColor)
                        .foregroundColor(textColor)
                        .cornerRadius(18)
                    
                    // Delivery state indicator
                    if isCurrentUser {
                        deliveryStateIcon
                    }
                }
                
                // Timestamp
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.7, alignment: isCurrentUser ? .trailing : .leading)
            
            if !isCurrentUser { Spacer() }
        }
    }
    
    private var bubbleColor: Color {
        if case .failed = message.deliveryState {
            return Color.red.opacity(0.2)
        }
        return isCurrentUser ? Color.blue : Color(.systemGray5)
    }
    
    private var textColor: Color {
        isCurrentUser ? .white : .primary
    }
    
    @ViewBuilder
    private var deliveryStateIcon: some View {
        switch message.deliveryState {
        case .sending:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 16, height: 16)
            
        case .sent:
            Image(systemName: "checkmark")
                .font(.caption2)
                .foregroundColor(.secondary)
            
        case .delivered:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundColor(.blue)
            
        case .failed:
            Button(action: onRetry) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
    }
}
