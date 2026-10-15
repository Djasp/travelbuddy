import Foundation
import CoreLocation

/// Eén verkeersmelding uit de NDW-feed (DATEX II), teruggebracht tot wat
/// nodig is om hem aan een route te koppelen.
struct TrafficIncident {
    enum Kind: Equatable {
        case accident
        case brokenDownVehicle
        case stationaryVehicle
        case obstruction
        case bridgeOpening
        case roadworks
        case closure
        case laneClosure
        case congestion
        case weather
        case other

        var label: String {
            switch self {
            case .accident: return "ongeval"
            case .brokenDownVehicle: return "pechgeval"
            case .stationaryVehicle: return "stilstaand voertuig"
            case .obstruction: return "obstructie"
            case .bridgeOpening: return "brugopening"
            case .roadworks: return "wegwerkzaamheden"
            case .closure: return "afsluiting"
            case .laneClosure: return "rijstrookafsluiting"
            case .congestion: return "file"
            case .weather: return "slecht weer"
            case .other: return "verkeersmelding"
            }
        }
    }

    let id: String
    let kind: Kind
    /// Werkzaamheden en brugopeningen: gepland, dus vaak al verwerkt in de mediaan.
    let isPlanned: Bool
    let points: [CLLocationCoordinate2D]
    /// Rijrichting waarop de melding betrekking heeft (graden, 0 = noord).
    let bearing: Double?
    let startTime: Date?
    let endTime: Date?

    private static let plannedCauses: Set<String> = ["roadMaintenance", "constructionWork"]

    /// Vertaalt het DATEX II-recordtype plus de detailcodes naar een soort.
    static func kind(recordType: String, details: Set<String>) -> Kind {
        switch recordType {
        case "Accident":
            return .accident
        case "VehicleObstruction":
            return details.contains("brokenDownVehicle") ? .brokenDownVehicle : .stationaryVehicle
        case "GeneralObstruction", "AnimalPresenceObstruction", "EnvironmentalObstruction", "InfrastructureDamageObstruction":
            return .obstruction
        case "GeneralNetworkManagement":
            return details.contains("bridgeSwingInOperation") ? .bridgeOpening : .other
        case "RoadOrCarriagewayOrLaneManagement":
            if details.contains("roadClosed") || details.contains("carriagewayClosures") { return .closure }
            if details.contains("laneClosures") || details.contains("narrowLanes") { return .laneClosure }
            return details.isDisjoint(with: plannedCauses) ? .other : .roadworks
        case "MaintenanceWorks", "ConstructionWorks", "Roadworks":
            return .roadworks
        case "AbnormalTraffic":
            return .congestion
        case "PoorEnvironmentConditions", "WeatherRelatedRoadConditions", "NonWeatherRelatedRoadConditions":
            return .weather
        default:
            return .other
        }
    }

    static func isPlanned(kind: Kind, details: Set<String>) -> Bool {
        kind == .roadworks || kind == .bridgeOpening || !details.isDisjoint(with: plannedCauses)
    }
}

// MARK: - Gzip

/// NDW levert de feed als .xml.gz zonder Content-Encoding, dus URLSession
/// pakt hem niet zelf uit. Foundation kent geen gzip, wel raw deflate.
enum Gzip {
    static func decompress(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        // Header (10) + trailer (8, CRC32 en lengte).
        guard bytes.count >= 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8 else { return nil }
        let flags = bytes[3]
        var index = 10
        if flags & 0x04 != 0 { // FEXTRA
            guard index + 2 <= bytes.count else { return nil }
            index += 2 + (Int(bytes[index]) | Int(bytes[index + 1]) << 8)
        }
        if flags & 0x08 != 0 { index = indexAfterZero(in: bytes, from: index) } // FNAME
        if flags & 0x10 != 0 { index = indexAfterZero(in: bytes, from: index) } // FCOMMENT
        if flags & 0x02 != 0 { index += 2 } // FHCRC
        guard index < bytes.count - 8 else { return nil }

        let deflate = Data(bytes[index..<(bytes.count - 8)]) as NSData
        // .zlib is bij Apple raw deflate (RFC 1951), precies wat gzip bevat.
        return try? deflate.decompressed(using: .zlib) as Data
    }

    private static func indexAfterZero(in bytes: [UInt8], from start: Int) -> Int {
        var index = start
        while index < bytes.count, bytes[index] != 0 { index += 1 }
        return index + 1
    }
}

// MARK: - DATEX II-parser

enum NDWDate {
    private static let formatter = ISO8601DateFormatter()

    static func parse(_ value: String) -> Date? {
        // NDW geeft tijden tot op de nanoseconde; ISO8601DateFormatter kan
        // daar niet mee overweg en seconden zijn ruim nauwkeurig genoeg.
        let trimmed = value.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return formatter.date(from: trimmed)
    }
}

/// Leest de situationRecords uit de NDW-feed `actueel_beeld` (DATEX II v3).
final class NDWSituationParser: NSObject, XMLParserDelegate {
    static func parse(_ data: Data) -> [TrafficIncident]? {
        let delegate = NDWSituationParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        return parser.parse() ? delegate.incidents : nil
    }

    private struct RecordBuilder {
        let id: String
        let type: String
        var details: Set<String> = []
        var points: [CLLocationCoordinate2D] = []
        var pendingLatitude: Double?
        var bearing: Double?
        var startTime: Date?
        var endTime: Date?
        var isSuspended = false

        func build() -> TrafficIncident {
            let kind = TrafficIncident.kind(recordType: type, details: details)
            return TrafficIncident(
                id: id,
                kind: kind,
                isPlanned: TrafficIncident.isPlanned(kind: kind, details: details),
                points: points,
                bearing: bearing,
                startTime: startTime,
                endTime: endTime
            )
        }
    }

    private static let detailElements: Set<String> = [
        "accidentType",
        "vehicleObstructionType",
        "obstructionType",
        "generalNetworkManagementType",
        "roadOrCarriagewayOrLaneManagementType",
        "roadMaintenanceType",
        "causeType",
    ]

    private var incidents: [TrafficIncident] = []
    private var record: RecordBuilder?
    private var text = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        text = ""
        guard Self.localName(elementName) == "situationRecord" else { return }
        record = RecordBuilder(
            id: attributeDict["id"] ?? UUID().uuidString,
            type: attributeDict["xsi:type"].map(Self.localName) ?? ""
        )
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if record != nil { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard var current = record else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ""

        switch Self.localName(elementName) {
        case "situationRecord":
            // Zonder coördinaten is een melding niet aan de route te koppelen.
            if !current.points.isEmpty && !current.isSuspended {
                incidents.append(current.build())
            }
            record = nil
            return
        case "latitude":
            current.pendingLatitude = Double(value)
        case "longitude":
            if let latitude = current.pendingLatitude, let longitude = Double(value) {
                current.points.append(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
            }
            current.pendingLatitude = nil
        case "posList":
            current.points += Self.coordinates(fromPosList: value)
        case "bearing":
            if current.bearing == nil { current.bearing = Double(value) }
        case "overallStartTime":
            current.startTime = NDWDate.parse(value)
        case "overallEndTime":
            current.endTime = NDWDate.parse(value)
        case "validityStatus":
            current.isSuspended = value == "suspended"
        case let name where Self.detailElements.contains(name) && !value.isEmpty:
            current.details.insert(value)
        default:
            break
        }
        record = current
    }

    /// posList is "lat lon lat lon ..." (WGS84).
    static func coordinates(fromPosList value: String) -> [CLLocationCoordinate2D] {
        let numbers = value.split(whereSeparator: \.isWhitespace).compactMap { Double($0) }
        return stride(from: 0, to: numbers.count - 1, by: 2).map {
            CLLocationCoordinate2D(latitude: numbers[$0], longitude: numbers[$0 + 1])
        }
    }

    private static func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }
}

// MARK: - Koppelen aan de route

enum RouteIncidentMatcher {
    /// Hoe ver een melding van de route mag liggen om mee te tellen.
    static let maximumDistanceMeters: Double = 300
    /// Geplande zaken (werkzaamheden, brugopeningen) zitten na een paar dagen
    /// al in de mediaan; alleen recent begonnen tellen als verklaring.
    static let plannedLookback: TimeInterval = 60 * 60
    /// Meldingen voor de andere rijrichting (bijv. A58 west terwijl jij oost
    /// rijdt) liggen wel dicht bij de route maar verklaren niets.
    static let maximumBearingDifference: Double = 100

    /// Meldingen langs de route, ongeplande eerst en daarbinnen de nieuwste eerst.
    static func incidents(
        along route: [CLLocationCoordinate2D],
        in incidents: [TrafficIncident],
        now: Date = Date()
    ) -> [TrafficIncident] {
        guard route.count >= 2 else { return [] }
        let projection = LocalProjection(referenceLatitude: route[0].latitude)
        let routePoints = route.map(projection.point)
        let bounds = Bounds(points: routePoints, margin: maximumDistanceMeters)

        let matches = incidents.filter { incident in
            guard isRelevant(incident, now: now) else { return false }
            guard let nearest = nearestSegment(
                to: incident.points.map(projection.point).filter(bounds.contains),
                route: routePoints
            ) else { return false }
            guard nearest.distance <= maximumDistanceMeters else { return false }
            if let bearing = incident.bearing {
                return angularDifference(bearing, nearest.bearing) <= maximumBearingDifference
            }
            return true
        }

        return matches.sorted { lhs, rhs in
            if lhs.isPlanned != rhs.isPlanned { return !lhs.isPlanned }
            return (lhs.startTime ?? .distantPast) > (rhs.startTime ?? .distantPast)
        }
    }

    static func isRelevant(_ incident: TrafficIncident, now: Date) -> Bool {
        if let end = incident.endTime, end <= now { return false }
        if let start = incident.startTime, start > now { return false }
        if incident.isPlanned {
            guard let start = incident.startTime, now.timeIntervalSince(start) <= plannedLookback else { return false }
        }
        return true
    }

    static func angularDifference(_ a: Double, _ b: Double) -> Double {
        let difference = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }

    private static func nearestSegment(to points: [Point], route: [Point]) -> (distance: Double, bearing: Double)? {
        var best: (distance: Double, bearing: Double)?
        for point in points {
            for (start, end) in zip(route, route.dropFirst()) {
                let distance = point.distance(toSegmentFrom: start, to: end)
                if distance < (best?.distance ?? .infinity) {
                    best = (distance, start.bearing(to: end))
                }
            }
        }
        return best
    }

    // Op de schaal van een rit volstaat een platte projectie in meters.
    private struct LocalProjection {
        let metersPerDegreeLatitude = 111_320.0
        let metersPerDegreeLongitude: Double

        init(referenceLatitude: Double) {
            metersPerDegreeLongitude = 111_320 * cos(referenceLatitude * .pi / 180)
        }

        func point(_ coordinate: CLLocationCoordinate2D) -> Point {
            Point(x: coordinate.longitude * metersPerDegreeLongitude, y: coordinate.latitude * metersPerDegreeLatitude)
        }
    }

    private struct Point {
        let x: Double
        let y: Double

        func distance(toSegmentFrom a: Point, to b: Point) -> Double {
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            let t = lengthSquared == 0 ? 0 : max(0, min(1, ((x - a.x) * dx + (y - a.y) * dy) / lengthSquared))
            return hypot(x - (a.x + t * dx), y - (a.y + t * dy))
        }

        /// Kompasrichting van self naar other (0 = noord, 90 = oost).
        func bearing(to other: Point) -> Double {
            let degrees = atan2(other.x - x, other.y - y) * 180 / .pi
            return degrees < 0 ? degrees + 360 : degrees
        }
    }

    private struct Bounds {
        let minX, maxX, minY, maxY: Double

        init(points: [Point], margin: Double) {
            minX = (points.map(\.x).min() ?? 0) - margin
            maxX = (points.map(\.x).max() ?? 0) + margin
            minY = (points.map(\.y).min() ?? 0) - margin
            maxY = (points.map(\.y).max() ?? 0) + margin
        }

        func contains(_ point: Point) -> Bool {
            (minX...maxX).contains(point.x) && (minY...maxY).contains(point.y)
        }
    }
}

// MARK: - Tekst

enum DelayCauseText {
    static let noIncidents = "Geen verkeersmelding op je route (waarschijnlijk drukte)"

    /// Bijv. "Ongeval bij Zeelandbrug, Zierikzee (sinds 13:05), plus 1 andere melding".
    static func text(for incident: TrafficIncident, place: String?, otherCount: Int, time: (Date) -> String) -> String {
        let label = incident.kind.label
        var text = label.prefix(1).uppercased() + label.dropFirst()
        text += place.map { " bij \($0)" } ?? " op je route"
        if let start = incident.startTime {
            text += " (sinds \(time(start)))"
        }
        if otherCount == 1 {
            text += ", plus 1 andere melding"
        } else if otherCount > 1 {
            text += ", plus \(otherCount) andere meldingen"
        }
        return text
    }
}
