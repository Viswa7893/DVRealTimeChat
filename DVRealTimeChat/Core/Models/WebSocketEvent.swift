//
//  WebSocketEvent.swift
//  DVRealTimeChat
//
//  Created by Durga Viswanadh on 14/12/25.
//

enum WebSocketEvent: Codable {
    case messageReceived(Message)
    case messageSent(messageId: String)
    case userTyping(userId: String, chatRoomId: String, isTyping: Bool)
    case userStatusChanged(userId: String, isOnline: Bool)
    case userRegistered  // New event for real-time user list updates
    case error(String)
    case connected
    case disconnected
    
    // For JSON encoding/decoding
    enum EventType: String, Codable {
        case messageReceived
        case messageSent
        case userTyping
        case userStatusChanged
        case userRegistered
        case error
        case connected
        case disconnected
    }
}

