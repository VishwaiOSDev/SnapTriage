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
        CategorizeScreenshotUseCase(textCategorizer: text, imageClassifier: image, imageLoader: loader)
    }

    @Test("Text-rich screenshot uses the text model and never touches the image path", .tags(.fast))
    func textRichUsesTextModel() async {
        let text = StubScreenshotCategorizer(.receipt)
        let loader = StubPhotoLibraryService(image: Fixture.image())
        let sut = makeSUT(text: text, image: StubImageContentClassifier(result: .photo), loader: loader)

        let category = await sut.execute(Fixture.ocrResult(transcript: "Total amount paid today"))

        #expect(category == .receipt)
        #expect(loader.cgImageRequested == false)
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

    @Test("Word count decides the route at the boundary", .tags(.fast), arguments: [
        ("one two three", true),     // 3 words  -> sparse -> image path
        ("one two three four", false) // 4 words  -> rich   -> text path
    ])
    func wordCountBoundary(transcript: String, expectsImagePath: Bool) async {
        let loader = StubPhotoLibraryService(image: Fixture.image())
        let sut = makeSUT(
            text: StubScreenshotCategorizer(.receipt),
            image: StubImageContentClassifier(result: .photo),
            loader: loader
        )

        let category = await sut.execute(Fixture.ocrResult(transcript: transcript))

        #expect(loader.cgImageRequested == expectsImagePath)
        #expect(category == (expectsImagePath ? .photo : .receipt))
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
