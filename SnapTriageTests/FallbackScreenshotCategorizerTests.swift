//
//  FallbackScreenshotCategorizerTests.swift
//  SnapTriageTests
//
//  Created by Vishweshwaran on 08/07/26.
//
//  End-to-end taxonomy behavior for the cheap-first cascade: the required MVP
//  fixtures resolve to the right category, and the clearly-identifiable ones do
//  so on the heuristic alone — never spending a foundation-model call.
//

import Testing
@testable import SnapTriage

@Suite("Classification taxonomy", .tags(.categorization, .fallback))
struct ClassificationTaxonomyTests {

    private static let alarm = """
    Alarm 7:00 AM
    Repeat Monday Tuesday Wednesday
    Snooze
    """

    private static let entertainment = """
    Dune Part Two
    Watch Trailer
    Cast and Crew
    IMDb
    Release Date March 1
    """

    private static let event = """
    Birthday Dinner
    Saturday July 20, 7:00 PM
    RSVP
    Add to Calendar
    Location
    """

    private static let receipt = """
    Order #123
    Subtotal $38.00
    Tax $4.00
    Total $42.00
    Paid
    """

    private static let otp = "Your verification code is 384726. Do not share it."

    @Test("Clear fixtures resolve on the heuristic with zero model calls", arguments: [
        (alarm, ScreenshotCategory.alarm),
        (entertainment, .entertainment),
        (event, .event),
        (receipt, .receipt),
        (otp, .otp),
    ])
    func clearFixturesSkipModel(transcript: String, expected: ScreenshotCategory) async {
        // The model is wired to return a wrong answer, so if it were consulted the
        // category would not match — proving the heuristic resolved it alone.
        let model = RecordingModelClassifier(category: .social)
        let sut = Fixture.categorize(model: model, loader: StubPhotoLibraryService(image: Fixture.image()))

        let result = await sut.execute(Fixture.ocrResult(transcript: transcript))

        #expect(result.category == expected)
        #expect(model.callCount == 0)
    }

    @Test("An alarm is never a game")
    func alarmIsNotGame() async {
        let sut = Fixture.categorize(loader: StubPhotoLibraryService(image: nil))
        let result = await sut.execute(Fixture.ocrResult(transcript: Self.alarm))
        #expect(result.category == .alarm)
        #expect(result.category != .game)
    }

    @Test("A movie screen is entertainment, not an event")
    func entertainmentIsNotEvent() async {
        let sut = Fixture.categorize(loader: StubPhotoLibraryService(image: nil))
        let result = await sut.execute(Fixture.ocrResult(transcript: Self.entertainment))
        #expect(result.category == .entertainment)
        #expect(result.category != .event)
    }

    @Test("A balance and card words are not a receipt")
    func balanceIsNotReceipt() async {
        // Heuristic can't clear receipt, so it reaches the model; whatever the
        // model says, the classifier must not call this a receipt on OCR alone.
        let model = RecordingModelClassifier(category: .finance)
        let sut = Fixture.categorize(model: model, loader: StubPhotoLibraryService(image: nil))

        let result = await sut.execute(
            Fixture.ocrResult(transcript: "Cash balance $1,200.00\nCard table\nCurrent score 900")
        )

        #expect(result.category != .receipt)
    }

    @Test("Weak, unfamiliar content is needs-review, not safe to delete")
    func unknownIsNeedsReview() async {
        let model = RecordingModelClassifier(nil)
        let sut = Fixture.categorize(model: model, loader: StubPhotoLibraryService(image: nil))

        let result = await sut.execute(Fixture.ocrResult(transcript: "qwerty asdf zxcv"))

        #expect(result.category == .other)
        #expect(result.disposition == .needsReview)
    }
}
