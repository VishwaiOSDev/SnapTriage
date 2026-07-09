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
