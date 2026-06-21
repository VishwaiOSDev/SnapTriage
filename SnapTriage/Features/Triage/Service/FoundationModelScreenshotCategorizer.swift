//
//  FoundationModelScreenshotCategorizer.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 20/06/26.
//

import Foundation
import FoundationModels

/// Classifies a screenshot transcript with Apple's on-device foundation model.
///
/// Output is constrained by guided generation (`@Generable`), so the model can
/// only return one of the known categories — no string parsing, no hallucinated
/// labels. Every call runs in a fresh, stateless session so transcripts from one
/// screenshot never bleed into the next.
///
/// Requires iOS 26+ *and* an enabled, downloaded model; callers must route
/// through ``FallbackScreenshotCategorizer`` for older OSes and degraded states.
@available(iOS 26.0, *)
struct FoundationModelScreenshotCategorizer {

    /// OCR transcripts are short; cap the prompt so a noisy screenshot can't blow the context window.
    private let maxTranscriptLength = 2_000

    private let model = SystemLanguageModel.default

    /// Pulls the model into memory now so the first ``category(for:)`` skips the cold-load
    /// stall. Safe to call repeatedly; once resident the model stays warm process-wide.
    func prewarm() {
        guard case .available = model.availability else { return }
        LanguageModelSession(model: model, instructions: Self.instructions).prewarm()
    }

    func category(for result: OCRResult) async throws -> ScreenshotCategory {
        guard case .available = model.availability else {
            throw CategorizationError.modelUnavailable
        }
        guard !result.transcript.isEmpty else { return .other }

        let transcript = String(result.transcript.prefix(maxTranscriptLength))
        let session = LanguageModelSession(model: model, instructions: Self.instructions)

        let response = try await session.respond(
            to: "Screenshot text to classify:\n\n\(transcript)",
            generating: GenerableScreenshotCategory.self
        )
        return response.content.domain
    }

    private static let instructions = Instructions {
        """
        You classify the on-screen text of a phone screenshot into exactly one category.
        Judge by the dominant purpose of the screen, not a single stray keyword.
        Prefer `other` over a wrong guess: only pick a category when the text clearly
        matches its definition. A bare number, a clock time, or a date is NOT enough on its own.

        Categories:
        - receipt: A purchase receipt, invoice, or order summary with line items, prices, or a total.
        - code: Source code, a terminal, or a config file with syntax and code keywords.
        - conversation: A chat or messaging thread with back-and-forth bubbles between people.
        - article: A news article, blog post, or long-form prose with a headline and body.
        - social: A social feed post with likes, follows, handles, hashtags, or reposts.
        - otp: ONLY an explicit one-time / verification / security code message that tells the
          user to enter or not share a code. A clock time, a phone number, an order number,
          or any unrelated digits are NOT an otp.
        - location: A map, directions, place listing, or business hours for a location.
        - travel: A boarding pass, flight, or travel ticket with gate, seat, or itinerary.
        - event: A calendar event, invite, or meeting with a date and time.
        - email: An email message or inbox with subject, sender, and recipients.
        - identity: A government or official ID — Aadhaar, passport, driver license, PAN,
          national ID — with an ID number, holder name, date of birth, or issuing authority.
        - document: A formal document or card — insurance card/policy, contract, agreement,
          certificate, official letter, or filled form — not covered by another category.
        - photo: A captured photo of a person, scene, object, food, or place, with little
          to no meaningful text.
        - other: Anything that does not clearly fit another category.
        """
    }
}

/// Guided-generation mirror of ``ScreenshotCategory``. Category definitions live
/// in ``FoundationModelScreenshotCategorizer/instructions`` — tune accuracy there.
@available(iOS 26.0, *)
@Generable
enum GenerableScreenshotCategory {
    case receipt
    case code
    case conversation
    case article
    case social
    case otp
    case location
    case travel
    case event
    case email
    case identity
    case document
    case photo
    case other

    var domain: ScreenshotCategory {
        switch self {
        case .receipt:      .receipt
        case .code:         .code
        case .conversation: .conversation
        case .article:      .article
        case .social:       .social
        case .location:     .location
        case .otp:          .otp
        case .travel:       .travel
        case .event:        .event
        case .email:        .email
        case .identity:     .identity
        case .document:     .document
        case .photo:        .photo
        case .other:        .other
        }
    }
}

enum CategorizationError: Error, Equatable {
    case modelUnavailable
}
