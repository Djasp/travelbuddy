import XCTest
@testable import TravelBuddy

final class TravelStatisticsTests: XCTestCase {
    func testMedianWithOddCount() {
        XCTAssertEqual(TravelStatistics.median(of: [30, 10, 20]), 20)
    }

    func testMedianWithEvenCount() {
        XCTAssertEqual(TravelStatistics.median(of: [10, 20, 30, 40]), 25)
    }

    func testMedianOfEmptyListIsNil() {
        XCTAssertNil(TravelStatistics.median(of: []))
    }

    func testMedianIgnoresOutlier() {
        // De mediaan mag niet omhoog getrokken worden door één extreme file.
        XCTAssertEqual(TravelStatistics.median(of: [20, 20, 20, 20, 90]), 20)
    }

    func testBaselineRequiresMinimumSamples() {
        let tooFew = samples(seconds: Array(repeating: 1200, count: TravelStatistics.minimumSamplesForBaseline - 1))
        XCTAssertNil(TravelStatistics.baselineSeconds(samples: tooFew))

        let enough = samples(seconds: Array(repeating: 1200, count: TravelStatistics.minimumSamplesForBaseline))
        XCTAssertEqual(TravelStatistics.baselineSeconds(samples: enough), 1200)
    }

    func testDelayMinutesClampsToZeroWhenFaster() {
        XCTAssertEqual(TravelStatistics.delayMinutes(currentSeconds: 1000, baselineSeconds: 1200), 0)
    }

    func testDelayMinutesRoundsToNearestMinute() {
        // 9,5 minuut verschil -> 10 minuten (afronden, niet afkappen).
        XCTAssertEqual(TravelStatistics.delayMinutes(currentSeconds: 1200 + 570, baselineSeconds: 1200), 10)
        // 20 seconden verschil -> 0 minuten.
        XCTAssertEqual(TravelStatistics.delayMinutes(currentSeconds: 1220, baselineSeconds: 1200), 0)
    }

    func testShortTravelTimesDoNotCountTowardBaseline() {
        // 3 minuten reistijd bij drempel 10 = je bent (bijna) op de bestemming.
        XCTAssertFalse(TravelStatistics.countsTowardBaseline(travelSeconds: 180, thresholdMinutes: 10))
    }

    func testTravelTimeAtThresholdCountsTowardBaseline() {
        XCTAssertTrue(TravelStatistics.countsTowardBaseline(travelSeconds: 600, thresholdMinutes: 10))
        XCTAssertTrue(TravelStatistics.countsTowardBaseline(travelSeconds: 1800, thresholdMinutes: 10))
    }

    private func samples(seconds: [TimeInterval]) -> [TravelSample] {
        seconds.map { TravelSample(date: Date(), seconds: $0) }
    }
}

final class DelayStateMachineTests: XCTestCase {
    func testBeginsExactlyAtThreshold() {
        var state = DelayStateMachine()
        XCTAssertEqual(state.evaluate(delayMinutes: 10, thresholdMinutes: 10, hasBaseline: true), .began)
        XCTAssertTrue(state.isDelayed)
    }

    func testNoRepeatedBeginWhileStillDelayed() {
        var state = DelayStateMachine()
        _ = state.evaluate(delayMinutes: 12, thresholdMinutes: 10, hasBaseline: true)
        XCTAssertEqual(state.evaluate(delayMinutes: 15, thresholdMinutes: 10, hasBaseline: true), .none)
        XCTAssertTrue(state.isDelayed)
    }

    func testEndsWhenDelayDropsBelowThreshold() {
        var state = DelayStateMachine()
        _ = state.evaluate(delayMinutes: 12, thresholdMinutes: 10, hasBaseline: true)
        XCTAssertEqual(state.evaluate(delayMinutes: 4, thresholdMinutes: 10, hasBaseline: true), .ended)
        XCTAssertFalse(state.isDelayed)
    }

    func testNoTransitionWhenNeverDelayed() {
        var state = DelayStateMachine()
        XCTAssertEqual(state.evaluate(delayMinutes: 3, thresholdMinutes: 10, hasBaseline: true), .none)
        XCTAssertFalse(state.isDelayed)
    }

    func testNoAlertsWithoutBaseline() {
        var state = DelayStateMachine()
        XCTAssertEqual(state.evaluate(delayMinutes: 60, thresholdMinutes: 10, hasBaseline: false), .none)
        XCTAssertFalse(state.isDelayed)
    }

    func testBaselineLossClearsDelayedStateWithoutNotification() {
        // Bijv. na reset van de geschiedenis midden in een vertraging:
        // geen (misleidende) "vertraging voorbij"-melding sturen.
        var state = DelayStateMachine()
        _ = state.evaluate(delayMinutes: 12, thresholdMinutes: 10, hasBaseline: true)
        XCTAssertEqual(state.evaluate(delayMinutes: 12, thresholdMinutes: 10, hasBaseline: false), .none)
        XCTAssertFalse(state.isDelayed)
    }
}

final class SampleStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "TravelBuddySampleStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testSamplesPersistAcrossInstances() {
        let store = SampleStore(defaults: defaults)
        store.add(TravelSample(date: Date(), seconds: 1200))
        store.add(TravelSample(date: Date(), seconds: 1500))

        let reloaded = SampleStore(defaults: defaults)
        XCTAssertEqual(reloaded.samples.map(\.seconds), [1200, 1500])
    }

    func testRemoveAllClearsPersistedSamples() {
        let store = SampleStore(defaults: defaults)
        store.add(TravelSample(date: Date(), seconds: 1200))
        store.removeAll()

        let reloaded = SampleStore(defaults: defaults)
        XCTAssertTrue(reloaded.samples.isEmpty)
    }

    func testOldSamplesArePrunedOnLoad() {
        let store = SampleStore(defaults: defaults)
        let ancient = Date().addingTimeInterval(-TravelStatistics.sampleRetention - 3600)
        store.add(TravelSample(date: ancient, seconds: 900))
        store.add(TravelSample(date: Date(), seconds: 1200))

        let reloaded = SampleStore(defaults: defaults)
        XCTAssertEqual(reloaded.samples.map(\.seconds), [1200])
    }
}
