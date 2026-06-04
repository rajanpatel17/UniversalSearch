//
//  DateUtility.swift
//  MintoakBase
//
//  Created by Rajan Patel on 10/12/25.
//

import Foundation

final class DateUtility {
    
    /// Returns today's date in "yyyy-MM-dd"
    static func getTodayDate() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Kolkata")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// Returns today's date in "EEE, dd MMM" → Ex: "Tue, 18 Nov"
    static func getTodayDateReadable() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Kolkata")
        formatter.dateFormat = "EEE, dd MMM"
        return formatter.string(from: Date())
    }
    
    func convertDateToSpecificFormat(date: String, currentFormat: String, desiredFormat: String) -> String {
        let updatedFormat = "en" != "en" ? desiredFormat.replacingOccurrences(of: "MMM", with: "MMMM") : desiredFormat
        let inputFormatter = DateFormatter()
        inputFormatter.locale = Locale(identifier: "en")
        inputFormatter.dateFormat = currentFormat
        let showDate = inputFormatter.date(from: date)
        inputFormatter.dateFormat = updatedFormat
        let resultString = inputFormatter.string(from: showDate ?? Date())
        return resultString
    }
    
    static func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"     // incoming format
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if let date = formatter.date(from: dateString) {
            formatter.dateFormat = "d MMM yyyy" // output format
            return formatter.string(from: date)
        }
        return dateString
    }
    
    static func formatToDate(_ dateString: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")

        guard let date = inputFormatter.date(from: dateString) else {
            return dateString
        }

        let calendar = Calendar.current
        let day = calendar.component(.day, from: date)

        // Ordinal suffix logic
        let suffix: String
        switch day % 100 {
        case 11, 12, 13:
            suffix = "th"
        default:
            switch day % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }

        let outputFormatter = DateFormatter()
        outputFormatter.locale = Locale(identifier: "en_US_POSIX")
        outputFormatter.dateFormat = "MMM yyyy"

        return "\(day)\(suffix) \(outputFormatter.string(from: date))"
    }

}
