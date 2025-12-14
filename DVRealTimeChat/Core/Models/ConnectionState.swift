//
//  ConnectionState.swift
//  DVRealTimeChat
//
//  Created by Durga Viswanadh on 14/12/25.
//

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case failed(String)
    
    var displayText: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .reconnecting: return "Reconnecting..."
        case .failed(let reason): return "Failed: \(reason)"
        }
    }
    
    var color: String {
        switch self {
        case .connected: return "green"
        case .connecting, .reconnecting: return "orange"
        case .disconnected, .failed: return "red"
        }
    }
}
