//
//  Notification+Extensions.swift
//  Claude Usage
//
//  Created by Claude Code on 2025-12-20.
//

import Foundation

extension Notification.Name {
    /// Posted when an account's credentials are added, removed, or changed
    static let credentialsChanged = Notification.Name("credentialsChanged")

    /// Posted when what the menu bar shows changes: icon style, the profile it
    /// shows, Follow Claude Code, or which accounts are listed
    static let multiProfileConfigChanged = Notification.Name("multiProfileConfigChanged")
}
