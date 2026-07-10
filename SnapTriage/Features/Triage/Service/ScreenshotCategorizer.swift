//
//  ScreenshotCategorizer.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 20/06/26.
//

import Foundation
import CoreGraphics
import NaturalLanguage

protocol ScreenshotCategorizer: Sendable {
    /// The image is supplied when the caller has it locally. Text-only classifiers ignore it;
    /// multimodal classifiers use it to disambiguate UI that OCR cannot describe.
    func category(for result: OCRResult, image: CGImage?) async -> ScreenshotCategory
    /// Loads any expensive backing model ahead of the first real call. No-op by default.
    func prewarm()
}

extension ScreenshotCategorizer {
    func category(for result: OCRResult) async -> ScreenshotCategory {
        await category(for: result, image: nil)
    }

    func prewarm() {}
}

/// On-device, no-network classifier. Lemmatizes the transcript (so `followers`
/// matches `follower`), mines structural signals via `NSDataDetector` and regex
/// (money, dates, codes, handles…), then scores every category against a single
/// declarative rule table. Falls back to `.other` when nothing clears the bar.
///
/// Rules are data, not code: adding a category is one row in `rules`. Serves as
/// the offline fallback when the foundation model is unavailable (iOS < 26,
/// Apple Intelligence off, or model not yet downloaded).
struct HeuristicScreenshotCategorizer: ScreenshotCategorizer {

    private let minimumScore: Double

    init(minimumScore: Double = 2.0) {
        self.minimumScore = minimumScore
    }

    func category(for result: OCRResult, image: CGImage?) async -> ScreenshotCategory {
        guard !result.transcript.isEmpty else { return .other }

        let features = Features(text: result.transcript)
        if Self.isDocumentLike(features) { return .document }
        if Self.isStructuredPlan(features) { return .other }

        let best = Self.rules
            .map { (category: $0.category, score: score($0, features)) }
            .max { $0.score < $1.score }

        guard let best,
              best.score >= minimumScore,
              Self.hasRequiredEvidence(for: best.category, features: features) else {
            return .other
        }
        return best.category
    }

    /// A reusable escape hatch for routines, study schedules, meal plans, chore lists, and
    /// similar task plans. They have no dedicated user-facing category, so `other` is correct.
    static func isStructuredPlan(_ result: OCRResult) -> Bool {
        guard !result.transcript.isEmpty else { return false }
        return isStructuredPlan(Features(text: result.transcript))
    }

    private func score(_ rule: CategoryRule, _ f: Features) -> Double {
        var total = rule.termWeight * Double(rule.terms.intersection(f.terms).count)
        for (signal, weight) in rule.signals { total += weight * f.value(for: signal) }
        for (phrase, weight) in rule.phrases where f.lowercased.contains(phrase) { total += weight }
        return total
    }
}

// MARK: - Rule table

/// A category's evidence: lemmatized `terms`, structural `signals`, and exact
/// `phrases`, each contributing weighted score. Tune accuracy here, not in code.
private struct CategoryRule {
    let category: ScreenshotCategory
    var terms: Set<String> = []
    var termWeight: Double = 1
    var signals: [Signal: Double] = [:]
    var phrases: [String: Double] = [:]
}

private extension HeuristicScreenshotCategorizer {
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

    static func hasRequiredEvidence(for category: ScreenshotCategory, features: Features) -> Bool {
        switch category {
        case .receipt:
            let anchorCount = receiptAnchors.intersection(features.terms).count
            let hasAmount = features.value(for: .money) > 0 || features.value(for: .amount) > 0
            // "Card" or a decimal number alone occur in games, wallets, and status screens.
            return anchorCount >= 2 || (anchorCount >= 1 && hasAmount)
        case .game:
            let gameCount = gameTerms.intersection(features.terms).count
            let strongCount = strongGameTerms.intersection(features.terms).count
            return (strongCount >= 1 && gameCount >= 2) || strongCount >= 2
        default:
            return true
        }
    }

    static func isDocumentLike(_ features: Features) -> Bool {
        let termCount = documentTerms.intersection(features.terms).count
        let fieldCount = features.value(for: .documentField)
        // This is deliberately structural rather than insurer-specific: records and membership
        // cards normally contain multiple labelled identifiers, while a chat mentioning a policy
        // does not. It only promotes toward the safer, useful disposition.
        return termCount >= 2 && fieldCount >= 1
    }

    static func isStructuredPlan(_ features: Features) -> Bool {
        // A weekday by itself is not enough: require recurring task quantities too. This avoids
        // treating calendar headings as plans while covering routines across several domains.
        features.value(for: .weekdayHeading) >= 2 && features.value(for: .taskQuantity) >= 2
    }

    static let rules: [CategoryRule] = [
        CategoryRule(
            category: .game,
            terms: gameTerms
        ),
        CategoryRule(
            category: .receipt,
            terms: ["total", "subtotal", "tax", "receipt", "invoice", "order", "amount", "qty", "payment", "transaction", "paid", "refund", "balance"],
            signals: [.money: 2, .amount: 0.75, .date: 0.5]
        ),
        CategoryRule(
            category: .code,
            signals: [.code: 0.5]
        ),
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
            terms: ["rsvp", "invite", "invited", "event", "calendar", "attend", "agenda", "meeting"],
            signals: [.date: 1],
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
            terms: ["aadhaar", "aadhar", "uidai", "passport", "license", "licence", "pan", "identification", "nationality", "issued", "expiry"],
            phrases: ["government of india": 3, "date of birth": 1.5, "unique identification": 3, "id no": 1.5]
        ),
        CategoryRule(
            category: .document,
            terms: documentTerms,
            signals: [.documentField: 1.5],
            phrases: ["policy number": 2.5, "member number": 2.5, "group number": 2.5, "terms and conditions": 1.5, "valid till": 1, "sum insured": 3]
        ),
    ]
}

// MARK: - Signals

private enum Signal {
    case money, amount, date, phone, link, address, handle, hashtag, code, otpCode
    case chatLines, proseLines, documentField, weekdayHeading, taskQuantity
}

// MARK: - Feature extraction

/// Signals mined once from a transcript, shared across every rule's score.
private struct Features {

    let lowercased: String
    /// Lowercased word tokens *and* their lemmas, so inflected forms match base keywords.
    let terms: Set<String>

    private let counts: [Signal: Double]

    func value(for signal: Signal) -> Double { counts[signal] ?? 0 }

    init(text: String) {
        lowercased = text.lowercased()
        terms = Self.terms(in: text)

        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        var dates = 0, phones = 0, links = 0, addresses = 0
        if let detector = Self.detector {
            let range = NSRange(text.startIndex..., in: text)
            detector.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                switch match?.resultType {
                case .date:        dates += 1
                case .phoneNumber: phones += 1
                case .link:        links += 1
                case .address:     addresses += 1
                default:           break
                }
            }
        }

        // Chat = many short, alternating lines; prose = several long lines.
        let shortLines = lines.filter { $0.count < 40 }.count
        let isChat = lines.count >= 6 && Double(shortLines) / Double(lines.count) > 0.6
        let isProse = lines.filter { $0.count > 60 }.count >= 3

        counts = [
            .money:     Double(Self.count(Self.money, in: text)),
            .amount:    Double(Self.count(Self.amount, in: text)),
            .date:      Double(dates),
            .phone:     Double(phones),
            .link:      Double(links),
            .address:   Double(addresses),
            .handle:    Double(Self.count(Self.handle, in: text)),
            .hashtag:   Double(Self.count(Self.hashtag, in: text)),
            // Capped 0/1: presence of a code-word adjacent to digits, not a count of all numbers.
            .otpCode:   Self.count(Self.otpCode, in: text) > 0 ? 1 : 0,
            .code:      Double(Self.codeSignals(in: text)),
            .chatLines: isChat ? 1 : 0,
            .proseLines: isProse ? 1 : 0,
            .documentField: Double(Self.count(Self.documentField, in: text)),
            .weekdayHeading: Double(Self.count(Self.weekdayHeading, in: text)),
            .taskQuantity: Double(Self.count(Self.taskQuantity, in: text)),
        ]
    }

    // MARK: Static extractors (built once, reused)

    private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType([.date, .phoneNumber, .link, .address]).rawValue
    )
    private static let money = regex(#"[$£€₹]\s?\d[\d,]*(\.\d{1,2})?"#)
    private static let amount = regex(#"(?<!\d)\d{1,3}(?:,\d{3})*\.\d{2}(?!\d)"#)
    private static let handle = regex(#"(?:^|\s)@\w{2,}"#)
    private static let hashtag = regex(#"(?:^|\s)#\w{2,}"#)
    // A code-word adjacent to a 3–8 digit run, in either order — the shape of a real OTP message.
    private static let otpCode = regex(#"(?i)(?:otp|passcode|one[\s-]?time|verification|security)[^\d\n]{0,20}\b\d{3,8}\b|\b\d{3,8}\b[^\d\n]{0,20}(?:otp|passcode|verification|code)"#)
    /// Generic labels found on IDs, membership cards, policies, and account records. The
    /// following number/value must stay on the same OCR line, avoiding false positives in prose.
    private static let documentField = regex(#"(?i)\b(?:policy|member|group|certificate|account|claim|subscriber|patient|provider|benefit|coverage|holder|insured)\s*(?:id|no\.?|number|#)?\s*(?::|#|-|\s)\s*(?:\d{3,}|[a-z]*\d[a-z0-9-]{2,})\b"#)
    private static let weekdayHeading = regex(#"(?im)^\s*(?:mon(?:day)?|tue(?:sday)?|wed(?:nesday)?|thu(?:rsday)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)\b"#)
    private static let taskQuantity = regex(#"(?i)\b(?:\d+\s*[x×]\s*\d+|\d+\s*(?:reps?|sets?|minutes?|mins?|hours?|hrs?|km|kilometers?|miles?|steps?|rounds?|pages?|questions?|tasks?))\b"#)

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern)
    }

    private static func count(_ regex: NSRegularExpression?, in text: String) -> Int {
        guard let regex else { return 0 }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func terms(in text: String) -> Set<String> {
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        var result: Set<String> = []
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lemma, options: options) { tag, range in
            let token = text[range].lowercased()
            if !token.isEmpty { result.insert(token) }
            if let lemma = tag?.rawValue.lowercased(), !lemma.isEmpty { result.insert(lemma) }
            return true
        }
        return result
    }

    private static func codeSignals(in text: String) -> Int {
        let symbols = Set("{};<>")
        let symbolCount = text.filter { symbols.contains($0) }.count
        let keywords = ["func", "let ", "var ", "return", "class", "struct", "import", "def ", "const", "void", "public", "private", "static", "=>", "->"]
        let lower = text.lowercased()
        let keywordHits = keywords.reduce(0) { $0 + (lower.contains($1) ? 1 : 0) }
        return symbolCount + keywordHits * 2
    }
}
