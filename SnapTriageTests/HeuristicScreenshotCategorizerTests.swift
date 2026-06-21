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
