//
//  MessageInputView.swift
//  DVRealTimeChat
//
//  Created by Durga Viswanadh on 14/12/25.
//

import SwiftUI

struct MessageInputView: View {
    @Binding var text: String
    let onSend: () -> Void
    let onChange: () -> Void
    
    @State private var isSending = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Text field
            TextField("Message", text: $text)
                .textFieldStyle(.roundedBorder)
                .onChange(of: text) { _ in
                    onChange()
                }
                .onSubmit {
                    sendMessage()
                }
            
            // Send button
            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(canSend ? .blue : .gray)
                    .scaleEffect(isSending ? 1.2 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSending)
            }
            .disabled(!canSend)
        }
        .padding()
        .background(Color(.systemBackground))
    }
    
    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func sendMessage() {
        guard canSend else { return }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            isSending = true
        }
        
        onSend()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation {
                isSending = false
            }
        }
    }
}
