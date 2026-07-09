//
//  FallbackScreenshotCategorizerTests.swift
//  SnapTriageTests
//
//  Created by Vishweshwaran on 08/07/26.
//

import Testing
@testable import SnapTriage

@Suite("Fallback categorizer", .tags(.categorization, .fallback))
struct FallbackScreenshotCategorizerTests {

    @Test("Primary verdict wins when it names a real category", .tags(.fast))
    func primaryVerdictWins() async {
        let fallback = StubScreenshotCategorizer(.social)
        let sut = FallbackScreenshotCategorizer(primary: { _ in .receipt }, fallback: fallback)

        let category = await sut.category(for: Fixture.ocrResult(transcript: "Total ₹499"))

        #expect(category == .receipt)
        #expect(fallback.categorizeCount == 0)
    }

    @Test("Primary `other` is rescued by a confident heuristic")
    func primaryOtherRescuedByHeuristic() async {
        let sut = FallbackScreenshotCategorizer(
            primary: { _ in .other },
            fallback: StubScreenshotCategorizer(.otp)
        )

        let category = await sut.category(for: Fixture.ocrResult(transcript: "Your verification code is 847291"))

        #expect(category == .otp)
    }

    @Test("Primary `other` stays `other` when the heuristic agrees")
    func primaryOtherStaysOtherWhenHeuristicAgrees() async {
        let sut = FallbackScreenshotCategorizer(
            primary: { _ in .other },
            fallback: StubScreenshotCategorizer(.other)
        )

        let category = await sut.category(for: Fixture.ocrResult(transcript: "random words here"))

        #expect(category == .other)
    }

    @Test("Delete-leaning primary verdict yields to keep-worthy heuristic evidence")
    func deleteLeaningVerdictYieldsToKeepEvidence() async {
        let sut = FallbackScreenshotCategorizer(
            primary: { _ in .conversation },
            fallback: StubScreenshotCategorizer(.document)
        )

        let category = await sut.category(for: Fixture.ocrResult(transcript: "Insurance card"))

        #expect(category == .document)
        #expect(category.disposition == .useful)
    }

    @Test("Delete-leaning primary verdict stands when the heuristic finds nothing to keep")
    func deleteLeaningVerdictStandsWithoutKeepEvidence() async {
        let sut = FallbackScreenshotCategorizer(
            primary: { _ in .social },
            fallback: StubScreenshotCategorizer(.other)
        )

        let category = await sut.category(for: Fixture.ocrResult(transcript: "so relatable lol"))

        #expect(category == .social)
    }

    @Test("Keep-leaning primary verdict is never second-guessed", .tags(.fast))
    func keepLeaningVerdictIsFinal() async {
        let fallback = StubScreenshotCategorizer(.conversation)
        let sut = FallbackScreenshotCategorizer(primary: { _ in .receipt }, fallback: fallback)

        let category = await sut.category(for: Fixture.ocrResult(transcript: "Total $12.00"))

        #expect(category == .receipt)
        #expect(fallback.categorizeCount == 0)
    }

    @Test("Primary failure falls back to the heuristic", .tags(.fast))
    func primaryFailureFallsBack() async {
        let sut = FallbackScreenshotCategorizer(
            primary: { _ in throw CategorizationError.modelUnavailable },
            fallback: StubScreenshotCategorizer(.conversation)
        )

        let category = await sut.category(for: Fixture.ocrResult(transcript: "hey\nsup\nnothing much"))

        #expect(category == .conversation)
    }
}
