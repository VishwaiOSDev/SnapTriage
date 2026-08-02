//
//  ManageClassificationCacheUseCase.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 01/08/26.
//

import Foundation

/// Reports and clears the recomputable side of the app's storage: OCR
/// transcripts and classification verdicts.
///
/// Deliberately does not touch triage decisions. Those are the user's own
/// verdicts, not a cache, and clearing them belongs behind "Start Over" in the
/// deck where the confirmation says so.
struct ManageClassificationCacheUseCase {

    let classifyLibrary: ClassifyLibraryUseCase
    let ocr: OCRStore

    func cachedCount() async -> Int {
        await classifyLibrary.cachedClassifications().count
    }

    func clear() async {
        await classifyLibrary.clearCache()
        await ocr.removeAll()
    }
}
