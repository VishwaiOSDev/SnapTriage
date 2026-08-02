//
//  ScreenshotCategorizer.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 20/06/26.
//

import Foundation
import CoreGraphics
import NaturalLanguage

enum TextSignal {
    case money, amount, date, phone, link, address, handle, hashtag, code, otpCode
    case chatLines, proseLines, documentField, identityNumber, governmentIssuer
    case weekdayHeading, taskQuantity, weekdayList
}

// MARK: - Feature extraction

/// Signals mined once from a transcript, shared across every rule's score.
struct TextFeatures {

    let lowercased: String
    /// Lowercased word tokens *and* their lemmas, so inflected forms match base keywords.
    let terms: Set<String>

    private let counts: [TextSignal: Double]

    func value(for signal: TextSignal) -> Double { counts[signal] ?? 0 }

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
            .identityNumber: Double(Self.count(Self.identityNumber, in: text)),
            .governmentIssuer: Double(Self.count(Self.governmentIssuer, in: text)),
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
    /// Common official-ID number shapes plus explicitly labelled identifiers.
    /// The label-based branch stays on one OCR line to avoid absorbing prose.
    private static let identityNumber = regex(#"(?im)(?:\b\d{4}[ -]\d{4}[ -]\d{4}\b|\b[a-z]{5}\d{4}[a-z]\b|\b[a-z]\d{7}\b|^[ \t]*(?:passport|visa|aadhaar|aadhar|uidai|uid|pan|national[ \t]+id|identity)[ \t]*(?:number|no\.?|#)?[ \t]*[:#-]?[ \t]*[a-z0-9<][a-z0-9< -]{4,20}[ \t]*$)"#)
    private static let governmentIssuer = regex(#"(?i)\b(?:government|republic|ministry|department|immigration|uidai|issuing authority|income tax)\b"#)
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
