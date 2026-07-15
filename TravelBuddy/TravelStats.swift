import Foundation

/// Eén reistijdmeting op een moment in de tijd.
struct TravelSample: Codable, Equatable {
    let date: Date
    let seconds: TimeInterval
}

enum TravelStatistics {
    /// Onder dit aantal metingen is er geen betrouwbare referentie
    /// en alarmeren we dus ook niet.
    static let minimumSamplesForBaseline = 5

    /// Metingen ouder dan dit venster tellen niet meer mee in de mediaan.
    static let sampleRetention: TimeInterval = 14 * 24 * 60 * 60

    static func median(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    /// Mediaan als referentie in plaats van gemiddelde:
    /// incidentele files trekken de referentie dan niet omhoog.
    static func baselineSeconds(samples: [TravelSample]) -> TimeInterval? {
        guard samples.count >= minimumSamplesForBaseline else { return nil }
        return median(of: samples.map(\.seconds))
    }

    /// Vertraging in hele minuten t.o.v. de referentie, nooit negatief.
    static func delayMinutes(currentSeconds: TimeInterval, baselineSeconds: TimeInterval) -> Int {
        let deltaMinutes = (currentSeconds - baselineSeconds) / 60
        return max(0, Int(deltaMinutes.rounded()))
    }

    /// Metingen korter dan de vertragingsdrempel betekenen "je bent (bijna) op
    /// de bestemming" — bijv. thuiswerken terwijl de bestemming je huis is.
    /// Die tellen niet mee: ze zouden de mediaan omlaagtrekken en daarmee
    /// later valse vertragingen veroorzaken.
    static func countsTowardBaseline(travelSeconds: TimeInterval, thresholdMinutes: Int) -> Bool {
        travelSeconds >= TimeInterval(thresholdMinutes) * 60
    }
}

enum DelayTransition {
    case none
    case began
    case ended
}

/// Houdt bij of we in "vertraagd"-toestand zitten en meldt alleen de
/// overgangen, zodat er per file precies één begin- en één eindnotificatie komt.
struct DelayStateMachine {
    private(set) var isDelayed = false

    mutating func evaluate(delayMinutes: Int, thresholdMinutes: Int, hasBaseline: Bool) -> DelayTransition {
        guard hasBaseline else {
            // Zonder referentie nooit alarmeren, ook geen "voorbij"-melding.
            isDelayed = false
            return .none
        }

        let delayedNow = delayMinutes >= thresholdMinutes
        defer { isDelayed = delayedNow }

        if delayedNow && !isDelayed {
            return .began
        }
        if !delayedNow && isDelayed {
            return .ended
        }
        return .none
    }
}

/// Persistente opslag van reistijdmetingen in UserDefaults.
final class SampleStore {
    private(set) var samples: [TravelSample]

    private let defaults: UserDefaults
    private let key = "travelSamples"
    private let maximumSampleCount = 2000

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([TravelSample].self, from: data) {
            samples = decoded
        } else {
            samples = []
        }
        prune()
    }

    func add(_ sample: TravelSample) {
        samples.append(sample)
        prune()
        persist()
    }

    func removeAll() {
        samples = []
        persist()
    }

    private func prune(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-TravelStatistics.sampleRetention)
        samples.removeAll { $0.date < cutoff }
        if samples.count > maximumSampleCount {
            samples.removeFirst(samples.count - maximumSampleCount)
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(samples) {
            defaults.set(data, forKey: key)
        }
    }
}
