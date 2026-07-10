//
//  ImageContentClassifier.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 20/06/26.
//

import Vision

/// Classifies a screenshot from its *pixels*, for shots the text model can't read —
/// a photo of a person, a signature, a scanned page with almost no extractable text.
/// Returns `nil` when the image is inconclusive, letting the caller fall back to text.
protocol ImageContentClassifier: Sendable {
    func category(for image: CGImage) async -> ScreenshotCategory?
}

/// On-device Vision classifier. A detected face means a person photo; otherwise the
/// scene-label taxonomy can identify broad game, document, and photo subjects.
struct VisionImageContentClassifier: ImageContentClassifier {

    /// Below this, a Vision label is noise — ignore it.
    private let minimumConfidence: Float = 0.25

    func category(for image: CGImage) async -> ScreenshotCategory? {
        let labels = await topLabels(in: image)
        if labels.contains(where: Self.gameHints.contains)     { return .game }
        if labels.contains(where: Self.documentHints.contains) { return .document }
        if await hasFace(in: image) { return .photo }
        if labels.contains(where: Self.photoHints.contains)    { return .photo }
        return nil
    }

    private func hasFace(in image: CGImage) async -> Bool {
        let request = DetectFaceRectanglesRequest()
        return (try? await request.perform(on: image))?.isEmpty == false
    }

    private func topLabels(in image: CGImage) async -> Set<String> {
        let request = ClassifyImageRequest()
        guard let observations = try? await request.perform(on: image) else { return [] }
        return Set(
            observations
                .filter { $0.confidence >= minimumConfidence }
                .map { $0.identifier.lowercased() }
        )
    }

    // Vision emits a hierarchical taxonomy; match on the leaf identifiers we care about.
    private static let documentHints: Set<String> = [
        "document", "paper", "paperwork", "text", "menu", "letter",
        "book", "page", "handwriting", "signature", "whiteboard", "card",
    ]
    private static let gameHints: Set<String> = [
        "game", "video game", "video game console", "game controller",
    ]
    private static let photoHints: Set<String> = [
        "people", "person", "portrait", "selfie", "crowd", "face",
        "outdoor", "nature", "plant", "tree", "flower", "animal", "pet",
        "dog", "cat", "food", "beverage", "vehicle", "car", "sky",
        "beach", "mountain", "landscape", "building", "art",
    ]
}
