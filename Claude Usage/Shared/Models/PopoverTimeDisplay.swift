//
//  PopoverTimeDisplay.swift
//  Claude Usage
//

import Foundation

enum PopoverTimeDisplay: String, CaseIterable {
    case resetTime      // "Resets Today 3:59pm"
    case remainingTime  // "Resets in 3h 45m"
    case both           // "Resets in 3h 45m (Today 3:59pm)"
}
