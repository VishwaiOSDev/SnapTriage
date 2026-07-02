//
//  PersistedDictionary.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 02/07/26.
//

import Foundation
import Synchronization

/// A string-keyed dictionary that survives relaunch. Reads and mutations are
/// synchronous against an in-memory copy loaded once at init; disk persistence
/// is write-behind — the first mutation of a burst schedules one debounced
/// snapshot write, so a swipe streak or a classify pass costs a single file
/// write, at most `debounce` behind. Call `flush()` when the scene backgrounds
/// to force any pending write out before the process may die.
///
/// A missing, corrupt, or version-mismatched file loads as empty rather than
/// failing: everything stored here can be recomputed or re-entered.
final class PersistedDictionary<Value: Codable & Sendable>: Sendable {

    private struct Envelope: Codable {
        let version: Int
        let entries: [String: Value]
    }

    private struct Guarded {
        var entries: [String: Value]
        var dirty = false
        var pendingWrite: Task<Void, Never>?
    }

    private static var formatVersion: Int { 1 }

    private let fileURL: URL
    private let debounce: Duration
    private let state: Mutex<Guarded>

    init(name: String, directory: URL, debounce: Duration = .milliseconds(500)) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("\(name).json")
        self.fileURL = fileURL
        self.debounce = debounce
        self.state = Mutex(Guarded(entries: Self.load(from: fileURL)))
    }

    subscript(id: String) -> Value? {
        state.withLock { $0.entries[id] }
    }

    func set(_ value: Value, for id: String) {
        mutate { $0[id] = value }
    }

    func remove(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        mutate { entries in ids.forEach { entries[$0] = nil } }
    }

    func removeAll() {
        mutate { $0.removeAll() }
    }

    func snapshot() -> [String: Value] {
        state.withLock { $0.entries }
    }

    /// Writes any pending changes out now instead of waiting for the debounce.
    func flush() {
        state.withLock {
            $0.pendingWrite?.cancel()
            $0.pendingWrite = nil
        }
        performWrite()
    }

    private func mutate(_ change: (inout [String: Value]) -> Void) {
        state.withLock { guarded in
            change(&guarded.entries)
            guarded.dirty = true
            guard guarded.pendingWrite == nil else { return }
            let debounce = debounce
            guarded.pendingWrite = Task.detached(priority: .utility) { [weak self] in
                guard (try? await Task.sleep(for: debounce)) != nil else { return }
                self?.performWrite()
            }
        }
    }

    private func performWrite() {
        let entries: [String: Value]? = state.withLock { guarded in
            guarded.pendingWrite = nil
            guard guarded.dirty else { return nil }
            guarded.dirty = false
            return guarded.entries
        }
        guard let entries,
              let data = try? JSONEncoder().encode(Envelope(version: Self.formatVersion, entries: entries))
        else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) -> [String: Value] {
        guard let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == formatVersion
        else { return [:] }
        return envelope.entries
    }
}
