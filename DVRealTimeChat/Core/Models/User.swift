//
//  User.swift
//  DVRealTimeChat
//
//  Created by Durga Viswanadh on 14/12/25.
//

import Foundation

struct User: Identifiable, Codable {
    let id: String
    let name: String
    let avatarURL: String?
    var isOnline: Bool
    var isTyping: Bool
}
