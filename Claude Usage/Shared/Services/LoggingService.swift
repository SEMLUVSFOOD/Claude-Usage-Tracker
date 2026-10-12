//
//  LoggingService.swift
//  Claude Usage
//
//  Created by Claude Code on 2025-12-20.
//

import Foundation
import os.log

/// Centralized logging service using os.log
/// Provides consistent logging across the application
final class LoggingService {
    static let shared = LoggingService()

    private let subsystem = Bundle.main.bundleIdentifier ?? "com.claudeusage"

    // Category-specific loggers
    private lazy var apiLogger = OSLog(subsystem: subsystem, category: "API")
    private lazy var storageLogger = OSLog(subsystem: subsystem, category: "Storage")
    private lazy var generalLogger = OSLog(subsystem: subsystem, category: "General")

    private init() {}

    // MARK: - API Logging

    func logAPIRequest(_ endpoint: String) {
        os_log("📤 API Request: %{public}@", log: apiLogger, type: .info, endpoint)
    }

    func logAPIResponse(_ endpoint: String, statusCode: Int) {
        os_log("📥 API Response: %{public}@ [%d]", log: apiLogger, type: .info, endpoint, statusCode)
    }

    func logAPIError(_ endpoint: String, error: Error) {
        os_log("❌ API Error: %{public}@ - %{public}@", log: apiLogger, type: .error, endpoint, error.localizedDescription)
    }

    // MARK: - Storage Logging

    func logStorageError(_ operation: String, error: Error) {
        os_log("❌ Storage Error [%{public}@]: %{public}@", log: storageLogger, type: .error, operation, error.localizedDescription)
    }

    // MARK: - Notification Logging

    // MARK: - UI Logging

    // MARK: - General Logging

    func log(_ message: String, type: OSLogType = .default) {
        os_log("%{public}@", log: generalLogger, type: type, message)
    }

    func logError(_ message: String, error: Error? = nil) {
        if let error = error {
            os_log("❌ %{public}@: %{public}@", log: generalLogger, type: .error, message, error.localizedDescription)
        } else {
            os_log("❌ %{public}@", log: generalLogger, type: .error, message)
        }
    }

    func logWarning(_ message: String) {
        os_log("⚠️ %{public}@", log: generalLogger, type: .fault, message)
    }

    func logInfo(_ message: String) {
        os_log("ℹ️ %{public}@", log: generalLogger, type: .info, message)
    }

}
