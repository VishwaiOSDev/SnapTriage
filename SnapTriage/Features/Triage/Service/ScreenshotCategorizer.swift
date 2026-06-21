//
//  ScreenshotCategorizer.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 20/06/26.
//

import Foundation
import NaturalLanguage

protocol ScreenshotCategorizer: Sendable {
    func category(for result: OCRResult) -> ScreenshotCategory
}

/// On-device, no-network classifier. Lemmatizes the transcript (so `followers`
/// matches `follower`), mines structural signals via `NSDataDetector` and regex
/// (money, dates, handles…), then scores every category against a single
/// declarative rule table. Falls back to `.other` when nothing clears the bar.
///
/// Rules are data, not code: adding a category is one row in `rules`, and the
/// same table is the feature spec for a future Core ML classifier.
struct HeuristicScreenshotCategorizer: ScreenshotCategorizer {

    private let minimumScore: Double

    init(minimumScore: Double = 2.0) {
        self.minimumScore = minimumScore
    }

    func category(for result: OCRResult) -> ScreenshotCategory {
        guard !result.transcript.isEmpty else { return .other }

        let features = Features(text: result.transcript)
        let best = Self.rules
            .map { (category: $0.category, score: score($0, features)) }
            .max { $0.score < $1.score }

        guard let best, best.score >= minimumScore else { return .other }
        return best.category
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
    static let rules: [CategoryRule] = [
        CategoryRule(
            category: .receipt,
            terms: ["total", "subtotal", "tax", "receipt", "invoice", "order", "amount", "qty", "payment", "change", "cash", "card"],
            signals: [.money: 2, .date: 0.5]
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
    ]
}

// MARK: - Signals

private enum Signal {
    case money, date, phone, link, address, handle, hashtag, code
    case chatLines, proseLines
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
            .date:      Double(dates),
            .phone:     Double(phones),
            .link:      Double(links),
            .address:   Double(addresses),
            .handle:    Double(Self.count(Self.handle, in: text)),
            .hashtag:   Double(Self.count(Self.hashtag, in: text)),
            .code:      Double(Self.codeSignals(in: text)),
            .chatLines: isChat ? 1 : 0,
            .proseLines: isProse ? 1 : 0,
        ]
    }

    // MARK: Static extractors (built once, reused)

    private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType([.date, .phoneNumber, .link, .address]).rawValue
    )
    private static let money = regex(#"[$£€₹]\s?\d[\d,]*(\.\d{1,2})?"#)
    private static let handle = regex(#"(?:^|\s)@\w{2,}"#)
    private static let hashtag = regex(#"(?:^|\s)#\w{2,}"#)

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
