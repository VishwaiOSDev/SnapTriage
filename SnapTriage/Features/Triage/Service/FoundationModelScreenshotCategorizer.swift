//
//  FoundationModelScreenshotCategorizer.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 20/06/26.
//

import Foundation
import FoundationModels
import CoreGraphics

/// Classifies screenshots with Apple's on-device foundation model.
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
            to: "Screenshot OCR text to classify:\n\n\(transcript)",
            generating: GenerableScreenshotCategory.self,
            options: GenerationOptions(samplingMode: .greedy)
        )
        return response.content.domain
    }

    /// Uses both the pixels and OCR when the system's multimodal model is available.
    /// OCR remains in the prompt because it is more accurate for small interface text.
    @available(iOS 27.0, *)
    func category(for result: OCRResult, image: CGImage) async throws -> ScreenshotCategory {
        guard case .available = model.availability else {
            throw CategorizationError.modelUnavailable
        }

        let transcript = String(result.transcript.prefix(maxTranscriptLength))
        let session = LanguageModelSession(model: model, instructions: Self.instructions)
        let response = try await session.respond(
            generating: GenerableScreenshotCategory.self,
            options: GenerationOptions(samplingMode: .greedy)
        ) {
            """
            Classify this phone screenshot. Use the image to identify its visual interface and
            use the OCR text below only as supporting evidence. The OCR can be incomplete,
            noisy, or ordered imperfectly.

            OCR text:
            \(transcript)
            """

            Attachment(image).label("screenshot")
        }
        return response.content.domain
    }

    private static let instructions = Instructions {
        """
        You classify one phone screenshot into exactly one category. When an image is present,
        use visual interface evidence first and OCR text as supporting evidence; OCR can be noisy.
        Judge by the dominant purpose of the whole screen, not a single stray keyword. Use `other`
        when the screen does not clearly belong to a listed category. Do not force an approximate
        match just because `other` is available.

        Categories:
        - game: Gameplay, a game lobby, game menu, score screen, or in-game store — player
          controls, game currency, levels, maps, characters, cards, or scoreboards. An in-game
          community or team screen is still `game`, not `social`.
        - receipt: A purchase receipt, invoice, bill, order summary/confirmation, or payment
          confirmation. It needs transaction evidence such as a merchant, order/receipt/invoice,
          a total, line items, or an amount paid or due; a balance or cards inside an app are not
          transaction evidence by themselves.
        - code: Source code, terminal output, logs, or a config file with syntax and code keywords.
        - conversation: A chat or messaging thread — messages people sent to each other,
          with senders and replies. Phone numbers or short label lines alone are NOT a chat.
        - article: A news article, blog post, or long-form prose with a headline and body.
        - social: A social media post, profile, or feed — likes, follows, handles, hashtags, reposts.
        - otp: A one-time / verification / security code message that tells the user to enter
          or not share a code. A clock time, phone number, or order number is NOT an otp.
        - location: A map, directions, place listing, reviews, or business hours for a location.
        - travel: A boarding pass, flight/train/bus ticket, hotel booking, or itinerary
          with gate, seat, PNR, check-in, or journey details.
        - event: A calendar event, invite, meeting, or reservation for a specific date
          and time — a calendar UI, an RSVP, or an invitation with attendees or a venue.
        - email: An email message or inbox with subject, sender, and recipients.
        - identity: A government or official ID — Aadhaar, passport, driver license, PAN,
          national ID — with an ID number, holder name, date of birth, or issuing authority.
        - document: A formal document or card — insurance/health/member card or policy,
          bank statement, contract, agreement, certificate, official letter, or filled
          form — often label/value pairs like policy, group, member, or certificate
          numbers, a holder name, and helpline numbers.
        - photo: A captured photo of a person, scene, object, food, or place, with little
          to no meaningful text.
        - alarm: An alarm or clock screen — an alarm list, an alarm being set or going off,
          with alarm/snooze/wake-up labels, repeat weekday toggles, or a bedtime schedule.
          A clock time or a number alone is NOT an alarm.
        - entertainment: A movie, TV, or streaming screen — a film/show detail page, trailer,
          cast and crew, episodes, cinema listings, or a movie-information screen. A release
          date or showtime alone does NOT make it an `event`.
        - finance: A banking, wallet, or investing screen — an account balance, statement,
          transactions, a portfolio, or budgeting — that is NOT a single purchase receipt.
        - shopping: A store, product, or cart screen — a product page, cart, checkout,
          wishlist, or listing, before any completed purchase.
        - settings: An app or system settings, preferences, or configuration screen — toggles,
          permissions, and options with no other clear purpose.
        - reminder: A reminders, to-do, or task-list screen with items to complete or due dates.
        - other: Nothing above fits even loosely.

        Tie-breakers:
        - Helpline, support, or emergency phone numbers on a card, receipt, or document
          do NOT make a `conversation` — any card naming an insurer, policy, plan,
          member, or ID number is `document` or `identity`, never `conversation`.
        - A verification code delivered inside a chat, SMS, or email is `otp`.
        - An order or payment confirmation with an amount is `receipt`, even inside an email or chat.
        - A booking confirmation for a journey or stay is `travel`, even with a price on screen.
        - An article or post shared inside a chat thread is `conversation` — classify the thread.
        - Alarm/snooze/wake-up controls with repeat weekday toggles are `alarm`, never `game`.
        - A movie or show detail page (trailer, cast, episodes) is `entertainment`, never `event`.
        - `event` needs event structure: an invitation, RSVP, attendees, a calendar UI, a
          meeting, a reservation, a venue, or "add to calendar" — not merely a date or time.
        - A weekday heading does NOT make an `event`. A workout routine, diet plan,
          timetable, or checklist organized by day is a plan with tasks, not an
          invitation — classify it `other` unless another category clearly fits.
        - A settings, dashboard, or unsupported screen with no better fit is `settings` or
          `other`; do not force it into the nearest category.
        """
    }
}

/// Guided-generation mirror of ``ScreenshotCategory``. Category definitions live
/// in ``FoundationModelScreenshotCategorizer/instructions`` — tune accuracy there.
@available(iOS 26.0, *)
@Generable
enum GenerableScreenshotCategory {
    case game
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
    case alarm
    case entertainment
    case finance
    case shopping
    case settings
    case reminder
    case other

    var domain: ScreenshotCategory {
        switch self {
        case .game:          .game
        case .receipt:       .receipt
        case .code:          .code
        case .conversation:  .conversation
        case .article:       .article
        case .social:        .social
        case .location:      .location
        case .otp:           .otp
        case .travel:        .travel
        case .event:         .event
        case .email:         .email
        case .identity:      .identity
        case .document:      .document
        case .photo:         .photo
        case .alarm:         .alarm
        case .entertainment: .entertainment
        case .finance:       .finance
        case .shopping:      .shopping
        case .settings:      .settings
        case .reminder:      .reminder
        case .other:         .other
        }
    }
}

enum CategorizationError: Error, Equatable {
    case modelUnavailable
}
