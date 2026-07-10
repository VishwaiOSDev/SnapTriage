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

    @Test("A game heuristic cannot replace the model's other verdict")
    func primaryOtherRejectsBroadGameHeuristic() async {
        let sut = FallbackScreenshotCategorizer(
            primary: { _ in .other },
            fallback: StubScreenshotCategorizer(.game)
        )

        let category = await sut.category(for: Fixture.ocrResult(transcript: "Monday\nBattle ropes 3 x 12"))

        #expect(category == .other)
    }

    @Test(
        "Any keep-worthy heuristic verdict rescues the model's other",
        arguments: [ScreenshotCategory.travel, .event, .email, .receipt, .otp, .identity, .document]
    )
    func primaryOtherRescuedByAnyUsefulVerdict(useful: ScreenshotCategory) async {
        let sut = FallbackScreenshotCategorizer(
            primary: { _ in .other },
            fallback: StubScreenshotCategorizer(useful)
        )

        let category = await sut.category(for: Fixture.ocrResult(transcript: "boarding pass gate 22"))

        #expect(category == useful)
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

    @Test("Multimodal primary can correct text-heavy app interfaces")
    func multimodalPrimaryWinsWhenAnImageIsAvailable() async {
        let sut = FallbackScreenshotCategorizer(
            primary: { _ in .social },
            multimodalPrimary: { _, _ in .game },
            fallback: StubScreenshotCategorizer(.other)
        )

        let category = await sut.category(
            for: Fixture.ocrResult(transcript: "Team chat and player updates"),
            image: Fixture.image()
        )

        #expect(category == .game)
    }

    @Test("A visual game verdict is not overturned by receipt-shaped OCR")
    func multimodalGameBeatsReceiptHeuristic() async {
        let sut = FallbackScreenshotCategorizer(
            multimodalPrimary: { _, _ in .game },
            fallback: StubScreenshotCategorizer(.receipt)
        )

        let category = await sut.category(
            for: Fixture.ocrResult(transcript: "Cash balance $1,200.00\nCard table"),
            image: Fixture.image()
        )

        #expect(category == .game)
    }

    @Test("A structured task plan overrides a model game verdict")
    func structuredPlanBeatsGameVerdict() async {
        let sut = FallbackScreenshotCategorizer(
            primary: { _ in .game },
            fallback: StubScreenshotCategorizer(.game)
        )
        let transcript = """
        Monday
        Battle ropes 3 x 12
        Tuesday
        Push ups 3 x 10
        Wednesday
        Plank 2 minutes
        """

        let category = await sut.category(for: Fixture.ocrResult(transcript: transcript))

        #expect(category == .other)
    }
}
