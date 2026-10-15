import Foundation
import CoreLocation
import MapKit

/// Zoekt bij een vertraging in de NDW-open data naar een verklaring op de route.
///
/// `actueel_beeld` is een momentopname: opgeloste incidenten verdwijnen eruit.
/// Daarom halen we hem op zodra de vertraging begint, niet achteraf.
final class TrafficInfoService {
    static let feedURL = URL(string: "https://opendata.ndw.nu/actueel_beeld.xml.gz")!

    private let session: URLSession
    private let geocoder = CLGeocoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Roept `completion` op de main queue aan met een korte omschrijving van
    /// de oorzaak, of nil als de verkeersinformatie niet op te halen was.
    func lookUpCause(along route: [CLLocationCoordinate2D], completion: @escaping (String?) -> Void) {
        var request = URLRequest(url: Self.feedURL)
        request.timeoutInterval = 20

        session.dataTask(with: request) { [weak self] data, response, _ in
            guard let self,
                  let data,
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let incidents = NDWSituationParser.parse(Gzip.decompress(data) ?? data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let matches = RouteIncidentMatcher.incidents(along: route, in: incidents)
            DispatchQueue.main.async {
                self.describe(matches, completion: completion)
            }
        }.resume()
    }

    private func describe(_ matches: [TrafficIncident], completion: @escaping (String?) -> Void) {
        guard let first = matches.first, let point = first.points.first else {
            completion(DelayCauseText.noIncidents)
            return
        }
        // NDW geeft geen wegnaam mee, alleen coördinaten.
        geocoder.reverseGeocodeLocation(CLLocation(latitude: point.latitude, longitude: point.longitude)) { placemarks, _ in
            completion(DelayCauseText.text(
                for: first,
                place: placemarks?.first.flatMap(Self.placeName),
                otherCount: matches.count - 1,
                time: Self.timeFormatter.string(from:)
            ))
        }
    }

    private static func placeName(_ placemark: CLPlacemark) -> String? {
        let road = placemark.thoroughfare ?? placemark.name
        let parts = [road, placemark.locality].compactMap { $0 }
        let unique = parts.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return unique.isEmpty ? nil : unique.joined(separator: ", ")
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coordinates = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))
        return coordinates
    }
}
