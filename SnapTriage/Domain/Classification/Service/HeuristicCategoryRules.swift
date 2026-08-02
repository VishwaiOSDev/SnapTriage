//
//  HeuristicCategoryRules.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 20/06/26.
//

import Foundation

/// A category's evidence: lemmatized `terms`, structural `signals`, and exact
/// `phrases`, each contributing weighted score. Tune accuracy here, not in code.
struct CategoryRule {
    let category: ScreenshotCategory
    var terms: Set<String> = []
    var termWeight: Double = 1
    var signals: [TextSignal: Double] = [:]
    var phrases: [String: Double] = [:]
}

extension HeuristicScreenshotCategorizer {
    static let gameTerms: Set<String> = [
        "game", "play", "player", "level", "score", "match", "battle",
        "quest", "mission", "leaderboard", "achievement", "inventory", "guild",
        "team", "win", "lose", "bet", "raise", "fold", "chip", "blind",
    ]

    /// Terms that rarely describe a task plan on their own. Text-only game classification must
    /// include these alongside other game evidence; visual classification on iOS 27 remains richer.
    static let strongGameTerms: Set<String> = [
        "game", "player", "score", "leaderboard", "achievement", "inventory", "guild",
        "bet", "raise", "fold", "chip", "blind",
    ]

    static let receiptAnchors: Set<String> = [
        "total", "subtotal", "receipt", "invoice", "order", "payment",
        "transaction", "purchased", "paid", "refund", "balance",
    ]

    static let documentTerms: Set<String> = [
        "policy", "insurance", "insured", "premium", "contract", "agreement",
        "certificate", "holder", "coverage", "beneficiary", "member", "group",
        "plan", "claim", "subscriber", "provider", "patient", "benefit",
    ]

    /// A verification/alarm/wake anchor. A clock time or bare number is never enough.
    static let alarmAnchors: Set<String> = ["alarm", "snooze", "wake", "wakeup", "bedtime"]

    static let entertainmentAnchors: Set<String> = [
        "trailer", "cast", "crew", "imdb", "episode", "episodes", "season", "seasons",
        "streaming", "showtime", "showtimes", "cinema", "director", "series", "premiere",
        "movie", "film",
    ]

    static let eventAnchors: Set<String> = [
        "rsvp", "invite", "invited", "calendar", "attend", "attendee", "attendees",
        "meeting", "reservation", "venue", "agenda", "host",
    ]

    static let financeTerms: Set<String> = [
        "balance", "account", "bank", "statement", "transaction", "transactions",
        "deposit", "withdraw", "withdrawal", "transfer", "portfolio", "invest",
        "investment", "stock", "stocks", "savings", "checking", "interest",
        "apr", "loan", "mortgage", "credit", "debit", "spending", "budget",
    ]

    static let shoppingAnchors: Set<String> = [
        "cart", "checkout", "wishlist", "shipping", "product", "seller", "coupon",
    ]
    static let shoppingTerms: Set<String> = [
        "cart", "checkout", "wishlist", "buy", "shipping", "delivery", "product",
        "sale", "discount", "coupon", "quantity", "seller", "store", "shop",
    ]

    static let settingsTerms: Set<String> = [
        "settings", "general", "privacy", "notifications", "bluetooth", "wifi",
        "cellular", "display", "brightness", "storage", "accessibility",
        "permissions", "preferences", "toggle", "enabled", "disabled",
    ]

    static let reminderAnchors: Set<String> = ["reminder", "reminders", "remind", "todo", "checklist"]

    static let identityTerms: Set<String> = [
        "aadhaar", "aadhar", "uidai", "passport", "visa", "license", "licence",
        "pan", "identification", "identity", "nationality", "citizenship",
        "surname", "birth", "issued", "issue", "expiry", "expires", "authority",
    ]

    static let identityFields: Set<String> = [
        "nationality", "citizenship", "surname", "birth", "sex", "gender",
        "issued", "issue", "expiry", "expires", "authority", "signature",
    ]

    static func hasRequiredEvidence(for category: ScreenshotCategory, features: TextFeatures) -> Bool {
        switch category {
        case .receipt:
            // A balance and a currency amount alone are not a receipt (a wallet,
            // a game table, a bank card all show those). Require either two
            // transaction anchors, or a non-balance anchor together with money.
            let anchors = receiptAnchors.intersection(features.terms)
            let nonBalanceAnchors = anchors.subtracting(["balance"])
            let hasMoney = features.value(for: .money) > 0 || features.value(for: .amount) > 0
            return anchors.count >= 2 || (!nonBalanceAnchors.isEmpty && hasMoney)
        case .game:
            let gameCount = gameTerms.intersection(features.terms).count
            let strongCount = strongGameTerms.intersection(features.terms).count
            return (strongCount >= 1 && gameCount >= 2) || strongCount >= 2
        case .identity:
            return isIdentityLike(features)
        case .alarm:
            // Alarm/clock evidence — a clock time or number alone is not an alarm.
            return !alarmAnchors.intersection(features.terms).isEmpty
        case .entertainment:
            // A release date or showtime alone does not make an entertainment screen.
            return !entertainmentAnchors.intersection(features.terms).isEmpty
        case .event:
            // Event-specific structure only; a date/time alone (a showtime, a
            // release date) is not an event.
            let hasAnchor = !eventAnchors.intersection(features.terms).isEmpty
            return hasAnchor || features.lowercased.contains("add to calendar")
        case .finance:
            // Two finance terms, so a lone "balance" (poker, a game) can't misfire.
            return financeTerms.intersection(features.terms).count >= 2
        case .shopping:
            return shoppingAnchors.intersection(features.terms).count >= 2
        case .settings:
            return settingsTerms.intersection(features.terms).count >= 2
        case .reminder:
            return !reminderAnchors.intersection(features.terms).isEmpty
        default:
            return true
        }
    }

    static func isDocumentLike(_ features: TextFeatures) -> Bool {
        let termCount = documentTerms.intersection(features.terms).count
        let fieldCount = features.value(for: .documentField)
        // This is deliberately structural rather than insurer-specific: records and membership
        // cards normally contain multiple labelled identifiers, while a chat mentioning a policy
        // does not. It only promotes toward the safer, useful disposition.
        return termCount >= 2 && fieldCount >= 1
    }

    /// Recognizes an official ID from an anchor plus corroborating structure.
    /// `visa` and `pan` need issuer/field/number context so a Visa payment card
    /// or the English word "pan" cannot become an identity false positive.
    static func isIdentityLike(_ features: TextFeatures) -> Bool {
        let text = features.lowercased
        let terms = features.terms
        let fieldCount = identityFields.intersection(terms).count
        let hasNumber = features.value(for: .identityNumber) > 0
        let hasIssuer = features.value(for: .governmentIssuer) > 0

        let hasAadhaar = !Set(["aadhaar", "aadhar", "uidai"]).isDisjoint(with: terms)
        if hasAadhaar && (hasNumber || hasIssuer || fieldCount >= 1) { return true }

        if terms.contains("passport") && (hasNumber || hasIssuer || fieldCount >= 1) {
            return true
        }

        let hasLicencePhrase = [
            "driver license", "driver's license", "driver licence", "driver's licence",
            "driving license", "driving licence",
        ].contains { text.contains($0) }
        if hasLicencePhrase && (hasNumber || hasIssuer || fieldCount >= 1) { return true }

        let hasNationalID = text.contains("national id") || text.contains("national identity")
        if hasNationalID && (hasNumber || hasIssuer || fieldCount >= 1) { return true }

        let hasVisaContext = terms.contains("visa") && (
            terms.contains("passport") || terms.contains("immigration") ||
            terms.contains("nationality") || text.contains("visa number") ||
            text.contains("visa no")
        )
        if hasVisaContext && (hasNumber || hasIssuer || fieldCount >= 1) { return true }

        let hasPANContext = terms.contains("pan") && (
            text.contains("permanent account") || text.contains("income tax") ||
            text.contains("pan number") || text.contains("pan no")
        )
        if hasPANContext && (hasNumber || hasIssuer || fieldCount >= 1) { return true }

        // OCR sometimes drops the document title while retaining the issuer,
        // number, and labelled fields. Require all three in that degraded case.
        return hasIssuer && hasNumber && fieldCount >= 1
    }

    static func isStructuredPlan(_ features: TextFeatures) -> Bool {
        // A weekday by itself is not enough: require recurring task quantities too. This avoids
        // treating calendar headings as plans while covering routines across several domains.
        features.value(for: .weekdayHeading) >= 2 && features.value(for: .taskQuantity) >= 2
    }

    static let rules: [CategoryRule] = [
        CategoryRule(category: .game, terms: gameTerms),
        CategoryRule(
            category: .receipt,
            terms: ["total", "subtotal", "tax", "receipt", "invoice", "order", "amount", "qty", "payment", "transaction", "paid", "refund", "balance"],
            signals: [.money: 2, .amount: 0.75, .date: 0.5]
        ),
        CategoryRule(category: .code, signals: [.code: 0.5]),
        CategoryRule(
            category: .conversation,
            terms: ["deliver", "delivered", "read", "sent", "send", "typing", "reply", "message", "text", "seen"],
            signals: [.phone: 1, .chatLines: 1.5]
        ),
        CategoryRule(
            category: .article,
            terms: ["subscribe", "publish", "published", "comment", "author", "follow", "story", "article", "headline"],
            signals: [.link: 0.5, .proseLines: 1],
            phrases: ["min read": 2]
        ),
        CategoryRule(
            category: .social,
            terms: ["like", "follower", "following", "repost", "retweet", "share", "comment", "post", "reply"],
            signals: [.handle: 1.5, .hashtag: 1.5]
        ),
        CategoryRule(
            category: .location,
            terms: ["direction", "route", "arrive", "mile", "review", "open", "hour", "map", "nearby", "destination", "closed"],
            signals: [.address: 3],
            phrases: ["open now": 1.5, "directions": 1.5]
        ),
        CategoryRule(
            category: .otp,
            terms: ["otp", "passcode"],
            signals: [.otpCode: 2.5],
            phrases: ["verification code": 3, "one-time": 2.5, "do not share": 2.5, "security code": 2, "your code is": 3]
        ),
        CategoryRule(
            category: .travel,
            terms: ["boarding", "gate", "seat", "flight", "departure", "arrival", "terminal", "passenger", "ticket", "baggage", "airline"],
            signals: [.date: 0.5],
            phrases: ["boarding pass": 3]
        ),
        CategoryRule(
            category: .event,
            terms: ["rsvp", "invite", "invited", "event", "calendar", "attend", "attendee", "attendees", "agenda", "meeting", "reservation", "venue", "host"],
            signals: [.date: 0.75],
            phrases: ["add to calendar": 3]
        ),
        CategoryRule(
            category: .email,
            terms: ["inbox", "reply", "forward", "unsubscribe", "sender", "draft"],
            signals: [.link: 0.3],
            phrases: ["subject:": 2, "to:": 1, "cc:": 1, "from:": 1, "unsubscribe": 1.5]
        ),
        CategoryRule(
            category: .identity,
            terms: identityTerms,
            termWeight: 1.5,
            signals: [.identityNumber: 2, .governmentIssuer: 2],
            phrases: [
                "government of india": 3, "date of birth": 1.5,
                "unique identification": 3, "permanent account number": 3,
                "income tax department": 3, "national identity": 3,
                "visa number": 2.5, "passport number": 2.5, "id no": 1.5,
            ]
        ),
        CategoryRule(
            category: .document,
            terms: documentTerms,
            signals: [.documentField: 1.5],
            phrases: ["policy number": 2.5, "member number": 2.5, "group number": 2.5, "terms and conditions": 1.5, "valid till": 1, "sum insured": 3]
        ),
        CategoryRule(
            category: .alarm,
            terms: ["alarm", "snooze", "wake", "wakeup", "bedtime", "dismiss", "ring", "alert", "repeat"],
            termWeight: 1.5,
            signals: [.weekdayList: 1.0],
            phrases: ["wake up": 2]
        ),
        CategoryRule(
            category: .entertainment,
            terms: ["trailer", "cast", "crew", "imdb", "episode", "episodes", "season", "seasons", "streaming", "stream", "showtime", "showtimes", "cinema", "director", "series", "premiere", "movie", "film", "watch", "runtime", "genre", "actor", "actress", "rating"],
            signals: [.date: 0.25]
        ),
        CategoryRule(
            category: .finance,
            terms: financeTerms,
            signals: [.money: 0.5]
        ),
        CategoryRule(
            category: .shopping,
            terms: shoppingTerms,
            phrases: ["add to cart": 3, "buy now": 2, "in stock": 1.5]
        ),
        CategoryRule(
            category: .settings,
            terms: settingsTerms
        ),
        CategoryRule(
            category: .reminder,
            terms: ["reminder", "reminders", "remind", "todo", "task", "tasks", "checklist", "due", "complete", "completed"],
            phrases: ["to-do": 1.5, "mark as complete": 2]
        ),
    ]
}
