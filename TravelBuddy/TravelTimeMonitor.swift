import Foundation
import CoreLocation
import MapKit
import UserNotifications

/// Centrale runtime-controller:
/// - meet op interval de reistijd (huidige locatie -> bestemming) via MapKit
/// - houdt de mediaan-referentie en actuele vertraging bij
/// - stuurt notificaties bij begin en einde van een vertraging
final class TravelTimeMonitor: NSObject, ObservableObject {
    @Published private(set) var isPaused = false
    @Published private(set) var isMeasuring = false
    @Published private(set) var lastTravelSeconds: TimeInterval?
    @Published private(set) var baselineSeconds: TimeInterval?
    @Published private(set) var delayMinutes = 0
    @Published private(set) var lastMeasurementDate: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var lastSampleIgnored = false

    private let preferences: AppPreferences
    private let sampleStore: SampleStore
    private var delayState = DelayStateMachine()
    private let locationManager = CLLocationManager()
    private var tickTimer: Timer?
    private var lastAttemptDate: Date?
    private var waitingForLocation = false

    init(preferences: AppPreferences, sampleStore: SampleStore = SampleStore()) {
        self.preferences = preferences
        self.sampleStore = sampleStore
        super.init()

        locationManager.delegate = self
        // Voor een reistijdschatting is grove nauwkeurigheid ruim voldoende
        // en dit spaart batterij/opzoektijd.
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters

        preferences.onDestinationChanged = { [weak self] in
            self?.handleDestinationChanged()
        }

        configureNotifications()
        startTicking()

        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        // Bij al verleende toestemming volgt de eerste meting via
        // locationManagerDidChangeAuthorization, die ook bij init afgaat.
    }

    deinit {
        tickTimer?.invalidate()
    }

    var isDelayed: Bool {
        delayState.isDelayed
    }

    // MARK: - Weergave

    /// Compacte tekst naast het menubalk-icoon, bijv. "32m" of "32m +9".
    var menuBarTitle: String {
        if isPaused { return "⏸" }
        guard preferences.destinationCoordinate != nil else { return "—" }
        guard let seconds = lastTravelSeconds else {
            if isMeasuring { return "…" }
            return lastError == nil ? "…" : "!"
        }
        let minutes = Self.wholeMinutes(seconds)
        if delayMinutes >= 1 {
            return "\(minutes)m +\(delayMinutes)"
        }
        return "\(minutes)m"
    }

    var travelTimeLine: String {
        if isPaused { return "Status: gepauzeerd" }
        guard preferences.destinationCoordinate != nil else { return "Stel eerst een bestemming in" }
        if let seconds = lastTravelSeconds {
            var line = "Reistijd: \(Self.formatMinutes(seconds))"
            if delayMinutes >= 1 {
                line += " (+\(delayMinutes) min)"
            }
            if lastSampleIgnored {
                line += " — telt niet mee (bij bestemming)"
            }
            return line
        }
        return isMeasuring ? "Reistijd meten…" : "Nog geen meting"
    }

    var baselineLine: String? {
        guard preferences.destinationCoordinate != nil else { return nil }
        if let baseline = baselineSeconds {
            return "Normaal (mediaan): \(Self.formatMinutes(baseline))"
        }
        let needed = TravelStatistics.minimumSamplesForBaseline
        return "Referentie na \(needed) metingen (\(min(sampleStore.samples.count, needed))/\(needed))"
    }

    var destinationLine: String? {
        preferences.destinationName.map { "Bestemming: \($0)" }
    }

    var lastMeasurementLine: String? {
        lastMeasurementDate.map { "Laatste meting: \(Self.timeFormatter.string(from: $0))" }
    }

    // MARK: - Acties

    func togglePause() {
        isPaused.toggle()
        if !isPaused {
            // Direct weer meten als het interval inmiddels verstreken is.
            tick()
        }
    }

    func measureNow() {
        guard !isMeasuring, !isPaused else { return }
        guard preferences.destinationCoordinate != nil else {
            lastError = "Geen bestemming ingesteld"
            return
        }

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            return // meten volgt via locationManagerDidChangeAuthorization
        case .denied, .restricted:
            lastError = "Locatietoegang geweigerd (zet aan via Systeeminstellingen > Privacy en beveiliging > Locatievoorzieningen)"
            return
        default:
            break
        }

        isMeasuring = true
        lastAttemptDate = Date()
        lastError = nil
        waitingForLocation = true
        locationManager.requestLocation()
    }

    /// Gooit de opgebouwde referentie weg en begint opnieuw met meten.
    func resetHistory() {
        sampleStore.removeAll()
        delayState = DelayStateMachine()
        baselineSeconds = nil
        delayMinutes = 0
        lastTravelSeconds = nil
        lastMeasurementDate = nil
        lastAttemptDate = nil
        lastSampleIgnored = false
        measureNow()
    }

    var sampleCount: Int {
        sampleStore.samples.count
    }

    // MARK: - Meetcyclus

    private func startTicking() {
        // Lichte 15s-tick die kijkt of het meetinterval verstreken is.
        // Dit blijft ook correct na slaapstand: na wake is het interval
        // gewoon verstreken en volgt direct een meting.
        tickTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tickTimer?.tolerance = 5
    }

    private func tick() {
        guard !isPaused, !isMeasuring else { return }
        let interval = TimeInterval(preferences.intervalMinutes * 60)
        if let last = lastAttemptDate, Date().timeIntervalSince(last) < interval {
            return
        }
        measureNow()
    }

    private func calculateRoute(from origin: CLLocationCoordinate2D) {
        guard let destination = preferences.destinationCoordinate else {
            finishMeasurement(error: "Geen bestemming ingesteld")
            return
        }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile
        request.requestsAlternateRoutes = true
        // Vertrek "nu" zorgt dat Apple de actuele verkeerssituatie meerekent.
        request.departureDate = Date()

        MKDirections(request: request).calculate { [weak self] response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                // Snelste route: dat is ook wat je in de auto zou kiezen.
                if let seconds = response?.routes.map(\.expectedTravelTime).min() {
                    self.record(travelSeconds: seconds)
                } else {
                    self.finishMeasurement(error: "Route berekenen mislukt: \(error?.localizedDescription ?? "onbekende fout")")
                }
            }
        }
    }

    private func record(travelSeconds: TimeInterval) {
        // Referentie bepalen op basis van eerdere metingen,
        // zodat de huidige meting zijn eigen vertraging niet maskeert.
        let baseline = TravelStatistics.baselineSeconds(samples: sampleStore.samples)

        // Reistijden korter dan de drempel = je bent (bijna) op de bestemming
        // (bijv. thuiswerkdag met bestemming thuis): niet opslaan en niet
        // meenemen in de vertragingsdetectie.
        let counts = TravelStatistics.countsTowardBaseline(
            travelSeconds: travelSeconds,
            thresholdMinutes: preferences.delayThresholdMinutes
        )
        if counts {
            sampleStore.add(TravelSample(date: Date(), seconds: travelSeconds))
        }
        lastSampleIgnored = !counts

        lastTravelSeconds = travelSeconds
        lastMeasurementDate = Date()
        baselineSeconds = baseline
        delayMinutes = (counts ? baseline : nil).map {
            TravelStatistics.delayMinutes(currentSeconds: travelSeconds, baselineSeconds: $0)
        } ?? 0

        // Genegeerde metingen tellen als "geen referentie": een eventueel
        // actieve vertraging wordt dan stil afgesloten (je bent er immers al),
        // zonder misplaatste "vertraging voorbij"-notificatie.
        let transition = delayState.evaluate(
            delayMinutes: delayMinutes,
            thresholdMinutes: preferences.delayThresholdMinutes,
            hasBaseline: counts && baseline != nil
        )
        switch transition {
        case .began:
            postDelayBeganNotification()
        case .ended:
            postDelayEndedNotification()
        case .none:
            break
        }

        lastError = nil
        isMeasuring = false
    }

    private func finishMeasurement(error: String) {
        waitingForLocation = false
        isMeasuring = false
        lastError = error
    }

    private func handleDestinationChanged() {
        resetHistory()
    }

    // MARK: - Notificaties

    private func configureNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func postDelayBeganNotification() {
        let destination = preferences.destinationName ?? "bestemming"
        let content = UNMutableNotificationContent()
        content.title = "Vertraging naar \(destination)"
        var body = "Reistijd is nu \(Self.formatMinutes(lastTravelSeconds ?? 0)) (+\(delayMinutes) min)."
        if let baseline = baselineSeconds {
            body += " Normaal: \(Self.formatMinutes(baseline))."
        }
        content.body = body
        content.sound = .default
        postNotification(content)
    }

    private func postDelayEndedNotification() {
        let destination = preferences.destinationName ?? "bestemming"
        let content = UNMutableNotificationContent()
        content.title = "Vertraging voorbij"
        content.body = "Reistijd naar \(destination) is weer normaal: \(Self.formatMinutes(lastTravelSeconds ?? 0))."
        content.sound = .default
        postNotification(content)
    }

    private func postNotification(_ content: UNMutableNotificationContent) {
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Formattering

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private static func wholeMinutes(_ seconds: TimeInterval) -> Int {
        max(0, Int((seconds / 60).rounded()))
    }

    private static func formatMinutes(_ seconds: TimeInterval) -> String {
        "\(wholeMinutes(seconds)) min"
    }
}

extension TravelTimeMonitor: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Op macOS bestaat alleen .authorizedAlways (geen "when in use").
        guard manager.authorizationStatus == .authorizedAlways else { return }
        // Vuurt ook bij app-start met al verleende toestemming:
        // dat is meteen de eerste meting.
        DispatchQueue.main.async { [weak self] in
            self?.measureNow()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard waitingForLocation, let location = locations.last else { return }
        waitingForLocation = false
        calculateRoute(from: location.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard waitingForLocation else { return }
        finishMeasurement(error: "Locatie ophalen mislukt: \(error.localizedDescription)")
    }
}

extension TravelTimeMonitor: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Ook tonen als de app "actief" is; als menubalk-app is er
        // toch geen eigen venster dat de melding vervangt.
        completionHandler([.banner, .sound])
    }
}
