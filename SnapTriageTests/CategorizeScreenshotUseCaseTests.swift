//
//  CategorizeScreenshotUseCaseTests.swift
//  SnapTriageTests
//
//  Created by Vishweshwaran on 20/06/26.
//

import Testing
@testable import SnapTriage

@Suite("Categorize cascade", .tags(.categorization, .routing))
struct CategorizeScreenshotUseCaseTests {

    // A screenshot the heuristic resolves with high confidence — a full receipt.
    private let receiptTranscript = """
    Order #123
    Subtotal $38.00
    Tax $4.00
    Total $42.00
    Paid
    """

    @Test("A high-confidence heuristic skips Vision and the model entirely", .tags(.fast))
    func highConfidenceHeuristicSkipsModel() async {
        let model = RecordingModelClassifier(category: .conversation)
        let loader = StubPhotoLibraryService(image: Fixture.image())
        let sut = Fixture.categorize(model: model, loader: loader)

        let result = await sut.execute(Fixture.ocrResult(transcript: receiptTranscript))

        #expect(result.category == .receipt)
        #expect(result.confidence == .high)
        #expect(result.source == .heuristic)
        #expect(model.callCount == 0)          // requirement: zero model calls for confident fixtures
        #expect(loader.cgImageRequested == false)
    }

    @Test("An ambiguous screenshot invokes the model exactly once", .tags(.fast))
    func ambiguousInvokesModelExactlyOnce() async {
        let model = RecordingModelClassifier(category: .conversation)
        let sut = Fixture.categorize(model: model, loader: StubPhotoLibraryService(image: Fixture.image()))

        let result = await sut.execute(Fixture.ocrResult(transcript: "hey what time is the thing tomorrow"))

        #expect(model.callCount == 1)          // requirement: exactly one model call for ambiguity
        #expect(result.category == .conversation)
        #expect(result.source == .foundationModelText)
    }

    @Test("An unresolved screenshot is needs-review, never safe to delete", .tags(.fast))
    func unresolvedIsNeedsReview() async {
        // Model unavailable + weak text: safe fallback, no crash, no auto-delete.
        let model = RecordingModelClassifier(nil)
        let sut = Fixture.categorize(model: model, loader: StubPhotoLibraryService(image: nil))

        let result = await sut.execute(Fixture.ocrResult(transcript: "lorem ipsum dolor sit amet"))

        #expect(result.category == .other)
        #expect(result.disposition == .needsReview)
        #expect(result.disposition != .safeToDelete)
    }

    @Test("Sparse text routes to Vision without the model")
    func sparseTextUsesVision() async {
        let model = RecordingModelClassifier(category: .conversation)
        let loader = StubPhotoLibraryService(image: Fixture.image())
        let sut = Fixture.categorize(
            vision: StubImageContentClassifier(result: .photo),
            model: model,
            loader: loader
        )

        let result = await sut.execute(Fixture.ocrResult(transcript: "hi"))

        #expect(result.category == .photo)
        #expect(result.source == .vision)
        #expect(loader.cgImageRequested)
        #expect(model.callCount == 0)
    }

    @Test("An inconclusive Vision result falls through to the model")
    func sparseInconclusiveFallsToModel() async {
        let model = RecordingModelClassifier(category: .otp)
        let sut = Fixture.categorize(
            vision: StubImageContentClassifier(result: nil),
            model: model,
            loader: StubPhotoLibraryService(image: Fixture.image())
        )

        let result = await sut.execute(Fixture.ocrResult(transcript: "hi"))

        #expect(model.callCount == 1)
        #expect(result.category == .otp)
    }

    @Test("A decoded OCR image is reused instead of loading the asset twice")
    func sourceImageIsReused() async {
        let model = RecordingModelClassifier(category: .conversation)
        let loader = StubPhotoLibraryService(image: Fixture.image())
        let sut = Fixture.categorize(
            vision: StubImageContentClassifier(result: nil),
            model: model,
            loader: loader
        )

        _ = await sut.execute(
            Fixture.ocrResult(transcript: "hello there"),
            sourceImage: Fixture.image()
        )

        #expect(loader.cgImageRequested == false)
        #expect(model.receivedImage)
    }

    @Test("Corroborated government ID evidence cannot become conversation")
    func identityCannotBecomeConversation() async {
        let model = RecordingModelClassifier(category: .conversation, usedImage: true)
        let sut = Fixture.categorize(
            vision: StubImageContentClassifier(result: .document),
            model: model,
            loader: StubPhotoLibraryService(image: Fixture.image())
        )
        let transcript = """
        PASSPORT
        Passport No A1234567
        Surname DOE
        Nationality CANADIAN
        Date of Birth 01 JAN 1990
        Helpline +1 800 555 0199
        """

        let result = await sut.execute(Fixture.ocrResult(transcript: transcript))

        #expect(result.category == .identity)
        #expect(result.confidence == .high)
        #expect(result.source == .heuristic)
        #expect(model.callCount == 0)
    }

    @Test("Keep-worthy heuristic evidence overrides a delete-leaning model verdict")
    func keepWorthyOverridesSafeModelVerdict() async {
        // "Total $50.00" scores receipt at medium — reaches the model, but a
        // safe-to-delete verdict must not overrule keep-worthy transaction evidence.
        let model = RecordingModelClassifier(category: .conversation)
        let sut = Fixture.categorize(model: model, loader: StubPhotoLibraryService(image: Fixture.image()))

        let result = await sut.execute(Fixture.ocrResult(transcript: "Total $50.00\nAmount paid"))

        #expect(result.category == .receipt)
        #expect(result.disposition == .useful)
    }

    @Test("A model `other` is rescued toward keep-worthy heuristic evidence")
    func modelOtherRescuedByKeepHeuristic() async {
        let model = RecordingModelClassifier(category: .other)
        let sut = Fixture.categorize(model: model, loader: StubPhotoLibraryService(image: Fixture.image()))

        let result = await sut.execute(Fixture.ocrResult(transcript: "Total $50.00\nAmount paid"))

        #expect(result.category == .receipt)
    }

    @Test("A structured task plan resolves to other without calling the model")
    func structuredPlanResolvesWithoutModel() async {
        let model = RecordingModelClassifier(category: .game)
        let sut = Fixture.categorize(model: model, loader: StubPhotoLibraryService(image: nil))
        let transcript = """
        Monday
        Battle ropes 3 x 12
        Tuesday
        Push ups 3 x 10
        Wednesday
        Plank 2 minutes
        """

        let result = await sut.execute(Fixture.ocrResult(transcript: transcript))

        #expect(result.category == .other)
        #expect(result.disposition == .needsReview)
        #expect(model.callCount == 0)
    }

    @Test("A visual game verdict is not overturned by receipt-shaped OCR")
    func multimodalGameBeatsReceiptOCR() async {
        let model = RecordingModelClassifier(category: .game, usedImage: true)
        let sut = Fixture.categorize(model: model, loader: StubPhotoLibraryService(image: Fixture.image()))

        let result = await sut.execute(
            Fixture.ocrResult(transcript: "Cash balance $1,200.00\nCard table\nCurrent score 900")
        )

        #expect(result.category == .game)
        #expect(result.source == .foundationModelMultimodal)
    }

    @Test("The model unavailable leaves a confident heuristic verdict intact", .tags(.fast))
    func modelUnavailableKeepsConfidentHeuristic() async {
        let model = RecordingModelClassifier(nil)
        let sut = Fixture.categorize(model: model, loader: StubPhotoLibraryService(image: nil))

        let result = await sut.execute(Fixture.ocrResult(transcript: receiptTranscript))

        #expect(result.category == .receipt)   // bypassed before the model was ever consulted
        #expect(model.callCount == 0)
    }

    @Test("Metrics record the routing path", .tags(.fast))
    func metricsRecordRouting() async {
        let metrics = RecordingClassificationMetrics()
        let model = RecordingModelClassifier(category: .conversation)
        let sut = Fixture.categorize(model: model, loader: StubPhotoLibraryService(image: Fixture.image()), metrics: metrics)

        _ = await sut.execute(Fixture.ocrResult(transcript: "hey what time is the thing tomorrow"))

        #expect(metrics.heuristicCalls == 1)
        #expect(metrics.foundationModelCalls == 1)
        #expect(metrics.resolutions[.foundationModelText] == 1)
    }

    @Test("Prewarm is forwarded to the model", .tags(.fast))
    func prewarmForwardsToModel() {
        let model = RecordingModelClassifier(nil)
        let sut = Fixture.categorize(model: model, loader: StubPhotoLibraryService(image: nil))

        sut.prewarm()

        #expect(model.prewarmCount == 1)
    }

    @Test("The foundation-model gate permits two requests and no more")
    func modelGateHasTwoLanes() async {
        let gate = FoundationModelGate(maxConcurrentRequests: 2)
        let probe = ConcurrencyProbe()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    await gate.run {
                        await probe.enter()
                        try? await Task.sleep(for: .milliseconds(20))
                        await probe.leave()
                    }
                }
            }
        }

        #expect(await probe.peakCount() == 2)
    }
}

private actor ConcurrencyProbe {
    private var active = 0
    private var peak = 0

    func enter() {
        active += 1
        peak = max(peak, active)
    }

    func leave() {
        active -= 1
    }

    func peakCount() -> Int { peak }
}
