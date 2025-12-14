//
//  ConnectionStatusView.swift
//  DVRealTimeChat
//
//  Created by Durga Viswanadh on 14/12/25.
//

import SwiftUI

struct ConnectionStatusView: View {
    let state: ConnectionState
    
    var body: some View {
        if state != .connected {
            HStack {
                Circle()
                    .fill(stateColor)
                    .frame(width: 8, height: 8)
                
                Text(state.displayText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
    
    private var stateColor: Color {
        switch state {
        case .connected:
            return .green
        case .connecting, .reconnecting:
            return .orange
        case .disconnected, .failed:
            return .red
        }
    }
}
