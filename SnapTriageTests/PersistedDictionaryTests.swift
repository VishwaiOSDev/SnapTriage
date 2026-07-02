//
//  PersistedDictionaryTests.swift
//  SnapTriageTests
//
//  Created by Vishweshwaran on 02/07/26.
//

import Foundation
import Testing
@testable import SnapTriage

@Suite("Persisted dictionary", .tags(.persistence))
struct PersistedDictionaryTests {

    private let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("PersistedDictionaryTests-\(UUID().uuidString)")

    private func makeSUT() -> PersistedDictionary<TriageDecision> {
        PersistedDictionary(name: "decisions", directory: directory)
    }

    @Test("Flushed entries survive a new instance at the same location")
    func roundTrip() {
        let first = makeSUT()
        first.set(.keep, for: "a")
        first.set(.markForDeletion, for: "b")
        first.flush()

        let second = makeSUT()
        #expect(second.snapshot() == ["a": .keep, "b": .markForDeletion])
    }

    @Test("Removed ids stay removed after reload")
    func removePersists() {
        let first = makeSUT()
        first.set(.keep, for: "a")
        first.set(.keep, for: "b")
        first.remove(["a"])
        first.flush()

        let second = makeSUT()
        #expect(second.snapshot() == ["b": .keep])
    }

    @Test("removeAll leaves an empty store after reload")
    func removeAllPersists() {
        let first = makeSUT()
        first.set(.keep, for: "a")
        first.flush()
        first.removeAll()
        first.flush()

        let second = makeSUT()
        #expect(second.snapshot().isEmpty)
    }

    @Test("A corrupt file loads as empty instead of failing")
    func corruptFileLoadsEmpty() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json{{".utf8).write(to: directory.appendingPathComponent("decisions.json"))

        #expect(makeSUT().snapshot().isEmpty)
    }

    @Test("A future format version loads as empty instead of misreading it")
    func versionMismatchLoadsEmpty() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"version": 999, "entries": {"a": "keep"}}"#.utf8)
            .write(to: directory.appendingPathComponent("decisions.json"))

        #expect(makeSUT().snapshot().isEmpty)
    }

    @Test("Unflushed mutations are still visible in memory")
    func inMemoryReadsDoNotNeedFlush() {
        let sut = makeSUT()
        sut.set(.markForDeletion, for: "a")

        #expect(sut["a"] == .markForDeletion)
        #expect(sut.snapshot() == ["a": .markForDeletion])
    }
}
