import Foundation
import CoreLocation

/// Persistente voorkeuren voor de app.
/// Alles wordt direct opgeslagen in UserDefaults zodra het wijzigt.
final class AppPreferences: ObservableObject {
    @Published var intervalMinutes: Int {
        didSet {
            // Clamp zonder oneindige didSet-recursie:
            // eerst corrigeren + return, pas anders opslaan.
            if intervalMinutes < 5 {
                intervalMinutes = 5
                return
            }
            if intervalMinutes > 60 {
                intervalMinutes = 60
                return
            }
            defaults.set(intervalMinutes, forKey: Keys.intervalMinutes)
        }
    }

    @Published var delayThresholdMinutes: Int {
        didSet {
            if delayThresholdMinutes < 1 {
                delayThresholdMinutes = 1
                return
            }
            if delayThresholdMinutes > 120 {
                delayThresholdMinutes = 120
                return
            }
            defaults.set(delayThresholdMinutes, forKey: Keys.delayThresholdMinutes)
        }
    }

    @Published private(set) var destinationName: String?
    @Published private(set) var destinationLatitude: Double?
    @Published private(set) var destinationLongitude: Double?

    /// Wordt gezet door TravelTimeMonitor zodat die de meetgeschiedenis
    /// kan resetten wanneer de bestemming echt wijzigt.
    var onDestinationChanged: (() -> Void)?

    var destinationCoordinate: CLLocationCoordinate2D? {
        guard let latitude = destinationLatitude, let longitude = destinationLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func setDestination(name: String, coordinate: CLLocationCoordinate2D) {
        // De mediaan-referentie is bestemmingsspecifiek. Alleen bij een echt
        // andere plek (>250 m) resetten we de geschiedenis; een her-geocode
        // van hetzelfde adres mag de opgebouwde referentie niet weggooien.
        let movedSignificantly: Bool
        if let current = destinationCoordinate {
            let oldLocation = CLLocation(latitude: current.latitude, longitude: current.longitude)
            let newLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            movedSignificantly = oldLocation.distance(from: newLocation) > 250
        } else {
            movedSignificantly = true
        }

        destinationName = name
        destinationLatitude = coordinate.latitude
        destinationLongitude = coordinate.longitude

        defaults.set(name, forKey: Keys.destinationName)
        defaults.set(coordinate.latitude, forKey: Keys.destinationLatitude)
        defaults.set(coordinate.longitude, forKey: Keys.destinationLongitude)

        if movedSignificantly {
            onDestinationChanged?()
        }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let intervalMinutes = "intervalMinutes"
        static let delayThresholdMinutes = "delayThresholdMinutes"
        static let destinationName = "destinationName"
        static let destinationLatitude = "destinationLatitude"
        static let destinationLongitude = "destinationLongitude"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Bestaande voorkeuren ophalen; anders defaults gebruiken.
        let storedInterval = defaults.object(forKey: Keys.intervalMinutes) as? Int
        let storedThreshold = defaults.object(forKey: Keys.delayThresholdMinutes) as? Int

        intervalMinutes = storedInterval ?? 10
        delayThresholdMinutes = storedThreshold ?? 10

        destinationName = defaults.object(forKey: Keys.destinationName) as? String
        destinationLatitude = defaults.object(forKey: Keys.destinationLatitude) as? Double
        destinationLongitude = defaults.object(forKey: Keys.destinationLongitude) as? Double

        // Startwaarden bij init alvast clamped houden.
        intervalMinutes = max(5, min(60, intervalMinutes))
        delayThresholdMinutes = max(1, min(120, delayThresholdMinutes))
    }
}
