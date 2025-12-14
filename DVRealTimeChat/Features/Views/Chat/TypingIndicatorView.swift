//
//  TypingIndicatorView.swift
//  DVRealTimeChat
//
//  Created by Durga Viswanadh on 14/12/25.
//

import SwiftUI

struct TypingIndicatorView: View {
    @State private var animationPhase = 0
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.gray)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animationPhase == index ? 1.3 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                        value: animationPhase
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemGray5))
        .cornerRadius(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            animationPhase = 1
        }
    }
}
