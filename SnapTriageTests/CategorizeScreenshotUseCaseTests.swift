//
//  CategorizeScreenshotUseCaseTests.swift
//  SnapTriageTests
//
//  Created by Vishweshwaran on 20/06/26.
//

import Testing
@testable import SnapTriage

@Suite("Categorize routing", .tags(.categorization, .routing))
struct CategorizeScreenshotUseCaseTests {

    private func makeSUT(
        text: StubScreenshotCategorizer,
        image: StubImageContentClassifier,
        loader: StubPhotoLibraryService
    ) -> CategorizeScreenshotUseCase {
        CategorizeScreenshotUseCase(categorizer: text, imageClassifier: image, imageLoader: loader)
    }

    @Test("Text-rich screenshots use the multimodal path when the OS supports it", .tags(.fast))
    func textRichUsesAvailableModelInput() async {
        let text = StubScreenshotCategorizer(.receipt)
        let loader = StubPhotoLibraryService(image: Fixture.image())
        let sut = makeSUT(text: text, image: StubImageContentClassifier(result: .photo), loader: loader)

        let category = await sut.execute(Fixture.ocrResult(transcript: "Total amount paid today"))

        #expect(category == .receipt)
        if #available(iOS 27.0, *) {
            #expect(loader.cgImageRequested)
            #expect(text.receivedImage)
        } else {
            #expect(loader.cgImageRequested == false)
            #expect(text.receivedImage == false)
        }
    }

    @Test("Sparse text routes to the image classifier")
    func sparseTextUsesImage() async {
        let loader = StubPhotoLibraryService(image: Fixture.image())
        let sut = makeSUT(
            text: StubScreenshotCategorizer(.other),
            image: StubImageContentClassifier(result: .photo),
            loader: loader
        )

        let category = await sut.execute(Fixture.ocrResult(transcript: "hi"))

        #expect(category == .photo)
        #expect(loader.cgImageRequested)
    }

    @Test("Inconclusive image falls back to the text model", .tags(.fallback))
    func imageInconclusiveFallsBackToText() async {
        let text = StubScreenshotCategorizer(.otp)
        let sut = makeSUT(
            text: text,
            image: StubImageContentClassifier(result: nil),
            loader: StubPhotoLibraryService(image: Fixture.image())
        )

        let category = await sut.execute(Fixture.ocrResult(transcript: "847291"))

        #expect(category == .otp)
        #expect(text.categorizeCount == 1)
    }

    @Test("Missing image falls back to the text model", .tags(.fallback))
    func missingImageFallsBackToText() async {
        let sut = makeSUT(
            text: StubScreenshotCategorizer(.other),
            image: StubImageContentClassifier(result: .photo),
            loader: StubPhotoLibraryService(image: nil)
        )

        let category = await sut.execute(Fixture.ocrResult(transcript: "hi"))

        #expect(category == .other)
    }

    @Test("Text-rich `other` verdict is rescued by the image classifier", .tags(.fallback))
    func textRichOtherRescuedByImage() async {
        let loader = StubPhotoLibraryService(image: Fixture.image())
        let sut = makeSUT(
            text: StubScreenshotCategorizer(.other),
            image: StubImageContentClassifier(result: .photo),
            loader: loader
        )

        let category = await sut.execute(Fixture.ocrResult(transcript: "daily specials fresh pasta salad"))

        #expect(category == .photo)
        #expect(loader.cgImageRequested)
    }

    @Test("Text-rich `other` verdict stays `other` when the image is inconclusive", .tags(.fallback))
    func textRichOtherStaysOtherWhenImageInconclusive() async {
        let sut = makeSUT(
            text: StubScreenshotCategorizer(.other),
            image: StubImageContentClassifier(result: nil),
            loader: StubPhotoLibraryService(image: Fixture.image())
        )

        let category = await sut.execute(Fixture.ocrResult(transcript: "one two three four five"))

        #expect(category == .other)
    }

    @Test("Word count only routes legacy text-only systems", .tags(.fast), arguments: [
        ("one two three", true),      // 3 words -> Vision first on iOS 26
        ("one two three four", false) // 4 words -> text first on iOS 26
    ])
    func wordCountBoundary(transcript: String, expectsImagePath: Bool) async {
        let loader = StubPhotoLibraryService(image: Fixture.image())
        let sut = makeSUT(
            text: StubScreenshotCategorizer(.receipt),
            image: StubImageContentClassifier(result: .photo),
            loader: loader
        )

        let category = await sut.execute(Fixture.ocrResult(transcript: transcript))

        if #available(iOS 27.0, *) {
            #expect(loader.cgImageRequested)
            #expect(category == .receipt)
        } else {
            #expect(loader.cgImageRequested == expectsImagePath)
            #expect(category == (expectsImagePath ? .photo : .receipt))
        }
    }

    @Test("Prewarm is forwarded to the text model", .tags(.fast))
    func prewarmForwardsToTextModel() {
        let text = StubScreenshotCategorizer(.other)
        let sut = makeSUT(
            text: text,
            image: StubImageContentClassifier(result: nil),
            loader: StubPhotoLibraryService(image: nil)
        )

        sut.prewarm()

        #expect(text.prewarmCount == 1)
    }
}
