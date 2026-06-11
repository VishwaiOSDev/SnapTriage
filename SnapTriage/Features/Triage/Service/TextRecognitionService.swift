//
//  TextRecognitionService.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 10/06/26.
//

import Vision

protocol TextRecognitionService: Sendable {
    func recognize(_ image: CGImage) async throws -> [OCRLine]
}

struct VisionTextRecognitionService: TextRecognitionService {

    func recognize(_ image: CGImage) async throws -> [OCRLine] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate          // .fast is only worth it for huge backlogs
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.minimumTextHeightFraction = 0.012      // ignore sub-pixel noise
        request.customWords = ["OTP", "PIN", "verification", "WiFi", "WPA"]

        do {
            let observations = try await request.perform(on: image)
            return observations.compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return OCRLine(
                    text: candidate.string,
                    confidence: candidate.confidence,
                    boundingBox: observation.boundingBox.cgRect
                )
            }
        } catch {
            throw TriageError.ocrFailed
        }
    }
}
