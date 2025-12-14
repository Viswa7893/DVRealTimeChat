//
//  ChatRoom.swift
//  DVRealTimeChat
//
//  Created by Durga Viswanadh on 14/12/25.
//

struct ChatRoom: Identifiable, Codable {
    let id: String
    let name: String
    let participants: [User]
    let isGroup: Bool
}
