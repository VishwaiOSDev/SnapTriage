//
//  CategoryBreakdownTests.swift
//  SnapTriageTests
//
//  Created by Vishweshwaran on 01/08/26.
//

import Testing
@testable import SnapTriage

@Suite("Category breakdown", .tags(.triage))
struct CategoryBreakdownTests {

    private func makeSUT(
        screenshots: [Screenshot],
        categories: [Screenshot.ID: ScreenshotCategory],
        decisions: SeededTriageDecisionStore = SeededTriageDecisionStore()
    ) -> LoadCategoryBreakdownUseCase {
        let service = FakePhotoLibraryService(screenshots: screenshots)
        let store = SeededCategoryStore(categories)
        return LoadCategoryBreakdownUseCase(
            loadScreenshots: LoadScreenshotsUseCase(service: service),
            classifyLibrary: Fixture.classifyLibrary(service: service, store: store),
            decisions: decisions
        )
    }

    @Test("Groups undecided screenshots by category, largest first", .tags(.fast))
    func groupsByCategoryLargestFirst() async throws {
        let sut = makeSUT(
            screenshots: [
                Fixture.screenshot(id: "1", byteSize: 100),
                Fixture.screenshot(id: "2", byteSize: 200),
                Fixture.screenshot(id: "3", byteSize: 300),
                Fixture.screenshot(id: "4", byteSize: 400)
            ],
            categories: ["1": .otp, "2": .social, "3": .otp, "4": .otp]
        )

        let breakdown = try await sut.execute()

        #expect(breakdown.groups.map(\.category) == [.otp, .social])
        #expect(breakdown.groups.first?.ids == ["1", "3", "4"])
        #expect(breakdown.groups.first?.byteSize == 800)
        #expect(breakdown.undecidedCount == 4)
    }

    @Test("Screenshots with a verdict are counted, never re-offered", .tags(.fast))
    func decidedScreenshotsAreExcluded() async throws {
        let sut = makeSUT(
            screenshots: [
                Fixture.screenshot(id: "1"),
                Fixture.screenshot(id: "2"),
                Fixture.screenshot(id: "3")
            ],
            categories: ["1": .social, "2": .social, "3": .social],
            decisions: SeededTriageDecisionStore(["1": .keep, "2": .markForDeletion])
        )

        let breakdown = try await sut.execute()

        #expect(breakdown.groups.map(\.ids) == [["3"]])
        #expect(breakdown.decidedCount == 2)
    }

    @Test("Unclassified screenshots are reported, not silently dropped", .tags(.fast))
    func unclassifiedAreReported() async throws {
        // The screen spends work already done, so it must never block on the
        // pipeline — but it must also not pretend the remainder doesn't exist.
        let sut = makeSUT(
            screenshots: [
                Fixture.screenshot(id: "1"),
                Fixture.screenshot(id: "2")
            ],
            categories: ["1": .social]
        )

        let breakdown = try await sut.execute()

        #expect(breakdown.groups.map(\.ids) == [["1"]])
        #expect(breakdown.unclassifiedCount == 1)
        #expect(breakdown.undecidedCount == 2)
    }

    @Test("A group's leaning comes from the category, not one member", .tags(.fast))
    func groupDispositionIsTheCategorys() async throws {
        let sut = makeSUT(
            screenshots: [Fixture.screenshot(id: "1"), Fixture.screenshot(id: "2")],
            categories: ["1": .social, "2": .otp]
        )

        let breakdown = try await sut.execute()
        let byCategory = Dictionary(
            uniqueKeysWithValues: breakdown.groups.map { ($0.category, $0.disposition) }
        )

        #expect(byCategory[.social] == .safeToDelete)
        #expect(byCategory[.otp] == .useful)
    }
}

@Suite("Bulk triage", .tags(.triage))
struct BulkTriageTests {

    @Test("Applying a verdict records it for every id", .tags(.fast))
    func appliesToEveryID() {
        let store = SeededTriageDecisionStore()
        let sut = ApplyBulkTriageUseCase(store: store)

        let receipt = sut.execute(.markForDeletion, for: .otp, ids: ["1", "2", "3"])

        #expect(store.allDecisions() == ["1": .markForDeletion, "2": .markForDeletion, "3": .markForDeletion])
        #expect(receipt.count == 3)
        #expect(receipt.previous.isEmpty)
    }

    @Test("Undo restores the exact prior state, not merely a blank one", .tags(.fast))
    func undoRestoresPriorVerdicts() {
        // "2" was already kept by hand. Undoing a bulk mark has to give that
        // verdict back, not throw it away along with the bulk one.
        let store = SeededTriageDecisionStore(["2": .keep])
        let apply = ApplyBulkTriageUseCase(store: store)
        let revert = RevertBulkTriageUseCase(store: store)

        let receipt = apply.execute(.markForDeletion, for: .social, ids: ["1", "2"])
        revert.execute(receipt)

        #expect(store.allDecisions() == ["2": .keep])
    }
}
