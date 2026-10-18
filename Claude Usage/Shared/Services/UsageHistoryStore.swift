//
//  UsageHistoryStore.swift
//  Claude Usage
//
//  Local usage history for the Stats page: one compact sample per account per
//  refresh (deduplicated), kept for 90 days in Application Support.
//

import Foundation
import Combine

/// One recorded reading. Short keys keep the history file small.
struct UsageSample: Codable, Equatable {
    /// When the reading was taken (epoch seconds; from `ClaudeUsage.lastUpdated`)
    let t: Int
    /// Session (5-hour window) usage, 0–100
    let s: Double
    /// Weekly usage, 0–100
    let w: Double
    /// Session window reset (epoch seconds) — identifies the 5-hour window
    let sr: Int
    /// Weekly window reset (epoch seconds) — identifies the week
    let wr: Int

    var date: Date { Date(timeIntervalSince1970: TimeInterval(t)) }
}

final class UsageHistoryStore: ObservableObject {
    static let shared = UsageHistoryStore()

    @Published private(set) var samples: [UUID: [UsageSample]] = [:]

    /// Don't store a reading more often than this unless the values moved.
    private static let minimumInterval = 5 * 60
    /// …by at least this many percentage points.
    private static let minimumChange = 1.0
    private static let retention: TimeInterval = 90 * 24 * 60 * 60

    private var saveWorkItem: DispatchWorkItem?

    private let fileURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Claude Usage", isDirectory: true)
            .appendingPathComponent("usage-history.json")
    }()

    private init() {
        load()
    }

    // MARK: - Recording

    func record(_ usage: ClaudeUsage, for profileId: UUID) {
        let sample = UsageSample(
            t: Int(usage.lastUpdated.timeIntervalSince1970),
            s: usage.effectiveSessionPercentage,
            w: usage.weeklyPercentage,
            sr: Self.minute(usage.sessionResetTime),
            wr: Self.minute(usage.weeklyResetTime)
        )
        var list = samples[profileId] ?? []
        if let last = list.last {
            // A cached reading (same timestamp) is not new data
            guard sample.t > last.t else { return }
            // An unused window's reset time is a placeholder that moves with
            // every reading; only a used window's reset marks a new window
            let newSessionWindow = sample.sr != last.sr && (sample.s > 0 || last.s > 0)
            let newWeeklyWindow = sample.wr != last.wr && (sample.w > 0 || last.w > 0)
            let moved = abs(sample.s - last.s) >= Self.minimumChange
                || abs(sample.w - last.w) >= Self.minimumChange
                || newSessionWindow || newWeeklyWindow
            guard moved || sample.t - last.t >= Self.minimumInterval else { return }
        }
        list.append(sample)
        let cutoff = Int(Date().addingTimeInterval(-Self.retention).timeIntervalSince1970)
        if let first = list.first, first.t < cutoff {
            list.removeAll { $0.t < cutoff }
        }
        samples[profileId] = list
        scheduleSave()
    }

    func deleteHistory(for profileId: UUID) {
        samples[profileId] = nil
        scheduleSave()
    }

    /// Reset times drift by seconds between readings; round to the minute so
    /// one window keeps one identity.
    private static func minute(_ date: Date) -> Int {
        Int((date.timeIntervalSince1970 / 60).rounded()) * 60
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: [UsageSample]].self, from: data) else { return }
        samples = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
            UUID(uuidString: key).map { ($0, value) }
        })
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.save() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: item)
    }

    private func save() {
        let snapshot = Dictionary(uniqueKeysWithValues: samples.map { ($0.key.uuidString, $0.value) })
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let url = fileURL
        // Only the (Sendable) bytes cross to the background queue
        DispatchQueue.global(qos: .utility).async {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            } catch {
                NSLog("UsageHistoryStore: save failed: \(error.localizedDescription)")
            }
        }
    }
}
