//
//  ScreenshotCategorizer.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 20/06/26.
//

import Foundation
import CoreGraphics
import NaturalLanguage

// MARK: - Model classifier abstraction

/// One verdict from the foundation model. `usedImage` records whether the
/// multimodal (pixels + OCR) path ran, so the caller can label the source
/// `foundationModelMultimodal` vs `foundationModelText` and tests can assert it.
struct ModelVerdict: Sendable, Equatable {
    let category: ScreenshotCategory
    let usedImage: Bool
}

/// The expensive, last-resort stage of the cascade. Kept behind a protocol so
/// the orchestrator can be driven by a recording test double that counts calls
/// and never touches Apple Intelligence.
///
/// Returns `nil` when the model cannot run at all (iOS < 26, Apple Intelligence
/// off, still downloading, or any inference error) — the caller then falls back
/// to the deterministic heuristic. Implementations must serialize inference (a
/// single on-device model session) and run each screenshot in a fresh context.
protocol ScreenshotModelClassifier: Sendable {
    func classify(ocr: OCRResult, image: CGImage?) async -> ModelVerdict?
    func prewarm()
}

extension ScreenshotModelClassifier {
    func prewarm() {}
}

// MARK: - Heuristic result

/// The rich outcome of one heuristic evaluation. Beyond the winning category it
/// exposes the runner-up, the raw score and margin, a confidence tier, the
/// matched evidence, and — when it abstains — why. The cascade uses all of this
/// to decide whether a deterministic verdict is trustworthy enough to skip the
/// foundation model.
struct HeuristicResult: Sendable, Equatable {
    let category: ScreenshotCategory
    let runnerUp: ScreenshotCategory?
    let score: Double
    /// Winner score minus runner-up score. A thin margin means an ambiguous
    /// screen even if the raw score is high.
    let margin: Double
    let tier: ClassificationConfidence
    let evidence: [ClassificationEvidence]
    /// Set when the winner did not clear the bar (below score, missing required
    /// evidence, structured plan, …). `nil` when a category was accepted.
    let abstentionReason: String?

    static let unresolved = HeuristicResult(
        category: .other, runnerUp: nil, score: 0, margin: 0,
        tier: .low, evidence: [], abstentionReason: "noEvidence"
    )
}

// MARK: - Heuristic classifier

/// On-device, no-network deterministic classifier. Lemmatizes the transcript (so
/// `followers` matches `follower`), mines structural signals via `NSDataDetector`
/// and regex (money, dates, codes, handles…), then scores every category against
/// a single declarative rule table.
///
/// Rules are data, not code: adding a category is one row in `rules`, plus an
/// optional required-evidence clause. This is the cheap, first stage of the
/// cascade — a high-confidence result here skips Vision and the foundation model
/// entirely — and doubles as the offline fallback when the model is unavailable
/// (iOS < 26, Apple Intelligence off, or model not yet downloaded).
struct HeuristicScreenshotCategorizer: Sendable {

    /// Below this a category is not eligible at all.
    private let minimumScore: Double
    /// A winner needs at least this score to *possibly* reach `.high`.
    private let highScore: Double
    /// …and at least this margin over the runner-up. A high raw score with a
    /// thin margin stays `.medium` so the cascade escalates it.
    private let highMargin: Double

    init(minimumScore: Double = 2.0, highScore: Double = 4.0, highMargin: Double = 1.5) {
        self.minimumScore = minimumScore
        self.highScore = highScore
        self.highMargin = highMargin
    }

    /// Back-compat convenience: the winning category (or `.other`). Prefer
    /// ``evaluate(_:)`` when confidence, evidence, or the runner-up matter.
    func category(for result: OCRResult, image: CGImage? = nil) async -> ScreenshotCategory {
        evaluate(result).category
    }

    /// The full deterministic evaluation. Pure and synchronous — feature
    /// extraction and scoring never touch I/O.
    func evaluate(_ result: OCRResult) -> HeuristicResult {
        guard !result.transcript.isEmpty else { return .unresolved }

        let features = Features(text: result.transcript)

        // Structural short-circuits. A membership card or record is protected
        // (promote to keep); a day/task routine has no category (resolve to other).
        if Self.isDocumentLike(features) {
            return HeuristicResult(
                category: .document, runnerUp: nil, score: highScore, margin: highMargin,
                tier: .high, evidence: [ClassificationEvidence("documentStructure")], abstentionReason: nil
            )
        }
        if Self.isStructuredPlan(features) {
            return HeuristicResult(
                category: .other, runnerUp: nil, score: minimumScore, margin: 0,
                tier: .medium, evidence: [ClassificationEvidence("structuredPlan")],
                abstentionReason: "structuredPlan"
            )
        }

        let scored = Self.rules
            .map { rule -> (category: ScreenshotCategory, score: Double, evidence: [ClassificationEvidence]) in
                let (score, evidence) = self.score(rule, features)
                return (rule.category, score, evidence)
            }
            .sorted { $0.score > $1.score }

        guard let best = scored.first else { return .unresolved }
        let runnerUp = scored.dropFirst().first { $0.score > 0 }
        let margin = best.score - (runnerUp?.score ?? 0)

        guard best.score >= minimumScore,
              Self.hasRequiredEvidence(for: best.category, features: features) else {
            return HeuristicResult(
                category: .other, runnerUp: best.category, score: best.score, margin: margin,
                tier: .low, evidence: best.evidence,
                abstentionReason: best.score < minimumScore ? "belowScore" : "missingRequiredEvidence"
            )
        }

        let tier: ClassificationConfidence = (best.score >= highScore && margin >= highMargin) ? .high : .medium
        return HeuristicResult(
            category: best.category, runnerUp: runnerUp?.category, score: best.score, margin: margin,
            tier: tier, evidence: best.evidence, abstentionReason: nil
        )
    }

    /// A reusable escape hatch for routines, study schedules, meal plans, chore lists, and
    /// similar task plans. They have no dedicated user-facing category, so `other` is correct.
    static func isStructuredPlan(_ result: OCRResult) -> Bool {
        guard !result.transcript.isEmpty else { return false }
        return isStructuredPlan(Features(text: result.transcript))
    }

    private func score(_ rule: CategoryRule, _ f: Features) -> (Double, [ClassificationEvidence]) {
        var total = 0.0
        var evidence: [ClassificationEvidence] = []

        let matchedTerms = rule.terms.intersection(f.terms)
        if !matchedTerms.isEmpty {
            let weight = rule.termWeight * Double(matchedTerms.count)
            total += weight
            evidence.append(ClassificationEvidence("terms", weight: weight))
        }
        for (signal, weight) in rule.signals {
            let value = f.value(for: signal)
            guard value > 0 else { continue }
            let contribution = weight * value
            total += contribution
            evidence.append(ClassificationEvidence(String(describing: signal), weight: contribution))
        }
        for (phrase, weight) in rule.phrases where f.lowercased.contains(phrase) {
            total += weight
            evidence.append(ClassificationEvidence("phrase:\(phrase)", weight: weight))
        }
        return (total, evidence)
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

    static func hasRequiredEvidence(for category: ScreenshotCategory, features: Features) -> Bool {
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
            terms: ["aadhaar", "aadhar", "uidai", "passport", "license", "licence", "pan", "identification", "nationality", "issued", "expiry"],
            phrases: ["government of india": 3, "date of birth": 1.5, "unique identification": 3, "id no": 1.5]
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

// MARK: - Signals

private enum Signal {
    case money, amount, date, phone, link, address, handle, hashtag, code, otpCode
    case chatLines, proseLines, documentField, weekdayHeading, taskQuantity, weekdayList
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
            // Distinct weekday names anywhere (an alarm's repeat toggles), capped so a
            // long list can't dominate. A lone weekday is not alarm evidence on its own.
            .weekdayList: min(Double(Self.count(Self.weekdayName, in: text)), 3),
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
    private static let weekdayName = regex(#"(?i)\b(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#)
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
