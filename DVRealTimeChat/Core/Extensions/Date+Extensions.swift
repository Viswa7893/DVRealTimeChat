//
//  Date+Extensions.swift
//  DVRealTimeChat
//
//  Created by Durga Viswanadh on 14/12/25.
//

import Foundation

extension Date {
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
    
    var chatTimestamp: String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(self) {
            return formatted(date: .omitted, time: .shortened)
        } else if calendar.isDateInYesterday(self) {
            return "Yesterday"
        } else {
            return formatted(date: .abbreviated, time: .omitted)
        }
    }
}
