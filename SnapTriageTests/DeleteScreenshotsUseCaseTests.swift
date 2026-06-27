//
//  DeleteScreenshotsUseCaseTests.swift
//  SnapTriageTests
//
//  Created by Vishweshwaran on 27/06/26.
//

import Testing
@testable import SnapTriage

@Suite("Delete screenshots", .tags(.review))
struct DeleteScreenshotsUseCaseTests {

    @Test("Forwards ids to the photo library", .tags(.fast))
    func forwardsIDs() async throws {
        let service = FakePhotoLibraryService()
        let sut = DeleteScreenshotsUseCase(service: service)

        try await sut.execute(["a", "b", "c"])

        #expect(service.deletedIDs == ["a", "b", "c"])
        #expect(service.deleteCallCount == 1)
    }

    @Test("Empty input never touches the library", .tags(.fast))
    func emptyIsNoOp() async throws {
        let service = FakePhotoLibraryService()
        let sut = DeleteScreenshotsUseCase(service: service)

        try await sut.execute([])

        #expect(service.deleteCallCount == 0)
    }

    @Test("User cancellation surfaces as deletionCancelled", .tags(.fast))
    func propagatesCancellation() async {
        let service = FakePhotoLibraryService(deleteError: TriageError.deletionCancelled)
        let sut = DeleteScreenshotsUseCase(service: service)

        await #expect(throws: TriageError.deletionCancelled) {
            try await sut.execute(["a"])
        }
    }

    @Test("A real failure surfaces as deletionFailed", .tags(.fast))
    func propagatesFailure() async {
        let service = FakePhotoLibraryService(deleteError: TriageError.deletionFailed)
        let sut = DeleteScreenshotsUseCase(service: service)

        await #expect(throws: TriageError.deletionFailed) {
            try await sut.execute(["a"])
        }
    }
}
