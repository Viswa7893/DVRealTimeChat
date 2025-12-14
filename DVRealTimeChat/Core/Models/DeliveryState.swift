//
//  DeliveryState.swift
//  DVRealTimeChat
//
//  Created by Durga Viswanadh on 14/12/25.
//

enum DeliveryState: Equatable {
    case sending
    case sent
    case delivered
    case failed(Error?)
    
    static func == (lhs: DeliveryState, rhs: DeliveryState) -> Bool {
        switch (lhs, rhs) {
        case (.sending, .sending),
             (.sent, .sent),
             (.delivered, .delivered):
            return true
        case (.failed, .failed):
            return true
        default:
            return false
        }
    }
}
