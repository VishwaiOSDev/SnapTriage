//
//  HeuristicScreenshotCategorizerTests.swift
//  SnapTriageTests
//
//  Created by Vishweshwaran on 20/06/26.
//

import Testing
@testable import SnapTriage

@Suite("Heuristic categorizer", .tags(.categorization, .heuristics, .fast))
struct HeuristicScreenshotCategorizerTests {

    private let sut = HeuristicScreenshotCategorizer()

    @Test("Classifies by dominant signals", arguments: [
        ("Total $42.00\nSubtotal $38.00\nTax $4.00\nCard payment", ScreenshotCategory.receipt),
        ("Government of India\nAadhaar\n1234 5678 9012\nDate of Birth 01/01/1990", .identity),
        ("Policy Number 998877\nSum Insured 500000\nPremium due\nInsured name", .document),
        ("Your verification code is 384726. Do not share it with anyone.", .otp),
    ])
    func classifiesByDominantSignal(transcript: String, expected: ScreenshotCategory) async {
        let category = await sut.category(for: Fixture.ocrResult(transcript: transcript))
        #expect(category == expected)
    }

    @Test("Phone-heavy insurance card is a document, not a conversation", .tags(.fallback))
    func insuranceCardBeatsPhoneSignals() async {
        let transcript = """
        Emergency Out of Province Coverage and Assistance is provided by
        AIG Travel Insurance under policy:
        9429051
        For emergency assistance call: 1-877-207-5018
        Outside North America, call collect: +1 819-566-3940
        INTERNATIONAL STUDENT INSURANCE CARD
        PLAN MEMBER
        DRUG, DENTAL & EXTENDED HEALTH GROUP NUMBER
        HOSPITAL, PHYSICIAN & ACCIDENT POLICY NUMBER
        CERTIFICATE ID
        DATE OF BIRTH (OPTIONAL)
        QUESTIONS: CALL 1-888-985-1552
        """

        let category = await sut.category(for: Fixture.ocrResult(transcript: transcript))

        #expect(category == .document)
    }

    @Test("Classifies generic game UI without an app-specific rule")
    func gameUIUsesGameplaySignals() async {
        let transcript = """
        Level 24
        Player score 12,400
        Battle mission
        Team leaderboard
        """

        let category = await sut.category(for: Fixture.ocrResult(transcript: transcript))

        #expect(category == .game)
    }

    @Test("A balance and card words are not enough to call a receipt")
    func receiptRequiresTransactionStructure() async {
        let transcript = "Cash balance $1,200.00\nCard table\nCurrent score 900"

        let category = await sut.category(for: Fixture.ocrResult(transcript: transcript))

        #expect(category != .receipt)
    }

    @Test("Resolves the new taxonomy categories from their evidence", arguments: [
        ("Alarm 7:00 AM\nRepeat Monday Tuesday Wednesday\nSnooze", ScreenshotCategory.alarm),
        ("Dune Part Two\nWatch Trailer\nCast and Crew\nIMDb\nRelease Date March 1", .entertainment),
        ("Birthday Dinner\nSaturday July 20, 7:00 PM\nRSVP\nAdd to Calendar\nLocation", .event),
    ])
    func classifiesNewCategories(transcript: String, expected: ScreenshotCategory) async {
        let result = sut.evaluate(Fixture.ocrResult(transcript: transcript))
        #expect(result.category == expected)
        #expect(result.tier == .high)
    }

    @Test("A high-confidence evaluation exposes evidence and a runner-up gap")
    func evaluateExposesConfidenceAndEvidence() async {
        let result = sut.evaluate(Fixture.ocrResult(transcript: "Total $42.00\nSubtotal $38.00\nTax $4.00\nPaid"))

        #expect(result.category == .receipt)
        #expect(result.tier == .high)
        #expect(result.margin > 0)
        #expect(!result.evidence.isEmpty)
        #expect(result.abstentionReason == nil)
    }

    @Test("An empty transcript abstains with a reason")
    func abstainsWithReason() async {
        let result = sut.evaluate(Fixture.ocrResult(transcript: ""))
        #expect(result.category == .other)
        #expect(result.abstentionReason != nil)
    }

    @Test("Recurring task plans stay other despite incidental game-like words")
    func structuredPlanIsOther() async {
        let transcript = """
        Monday
        Battle ropes 3 x 12
        Squats 3 sets
        Tuesday
        Push ups 3 x 10
        Plank 2 minutes
        Wednesday
        Lunges 3 sets
        """

        let category = await sut.category(for: Fixture.ocrResult(transcript: transcript))

        #expect(category == .other)
    }

    @Test("Empty transcript is other", .tags(.fallback))
    func emptyTranscriptIsOther() async {
        let category = await sut.category(for: Fixture.ocrResult(transcript: ""))
        #expect(category == .other)
    }

    @Test("Text below the score threshold is other", .tags(.fallback))
    func weakSignalIsOther() async {
        let category = await sut.category(for: Fixture.ocrResult(transcript: "lorem ipsum dolor sit amet"))
        #expect(category == .other)
    }
}
