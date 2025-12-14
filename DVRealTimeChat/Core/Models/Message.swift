//
//  Message.swift
//  DVRealTimeChat
//
//  Created by Durga Viswanadh on 14/12/25.
//

import Foundation

struct Message: Identifiable, Codable, Equatable {
    let id: String
    let senderId: String
    let senderName: String
    let content: String
    let timestamp: Date
    let chatRoomId: String
    var deliveryState: DeliveryState // Local only, not encoded/decoded
    
    enum CodingKeys: String, CodingKey {
        case id, senderId, senderName, content, timestamp, chatRoomId
    }
    
    // MARK: - Custom Decodable
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        senderId = try container.decode(String.self, forKey: .senderId)
        senderName = try container.decode(String.self, forKey: .senderName)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        chatRoomId = try container.decode(String.self, forKey: .chatRoomId)
        
        // Default to delivered for messages received from server
        deliveryState = .delivered
    }
    
    // MARK: - Custom Encodable
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(senderId, forKey: .senderId)
        try container.encode(senderName, forKey: .senderName)
        try container.encode(content, forKey: .content)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(chatRoomId, forKey: .chatRoomId)
        // deliveryState is intentionally not encoded
    }
    
    // MARK: - Manual Initializer (for creating messages locally)
    init(
        id: String,
        senderId: String,
        senderName: String,
        content: String,
        timestamp: Date,
        chatRoomId: String,
        deliveryState: DeliveryState = .sending
    ) {
        self.id = id
        self.senderId = senderId
        self.senderName = senderName
        self.content = content
        self.timestamp = timestamp
        self.chatRoomId = chatRoomId
        self.deliveryState = deliveryState
    }
}
