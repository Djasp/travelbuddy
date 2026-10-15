import XCTest
import CoreLocation
@testable import TravelBuddy

final class GzipTests: XCTestCase {
    func testDecompressesPlainGzip() throws {
        let data = try XCTUnwrap(Data(base64Encoded: "H4sIAAAAAAAC/7NJtPNzCbfRT7QDAGSKv3QKAAAA"))
        XCTAssertEqual(Gzip.decompress(data).map { String(decoding: $0, as: UTF8.self) }, "<a>NDW</a>")
    }

    func testSkipsFileNameInHeader() throws {
        // Zoals `gzip` op de command line hem maakt: met FNAME-veld.
        let data = try XCTUnwrap(Data(base64Encoded: "H4sICAAAAAAC/2FjdHVlZWxfYmVlbGQueG1sALNJtPNzCbfRT7QDAGSKv3QKAAAA"))
        XCTAssertEqual(Gzip.decompress(data).map { String(decoding: $0, as: UTF8.self) }, "<a>NDW</a>")
    }

    func testReturnsNilForNonGzipData() {
        XCTAssertNil(Gzip.decompress(Data("<xml>niet ingepakt</xml>".utf8)))
    }
}

final class NDWSituationParserTests: XCTestCase {
    private let feed = """
    <?xml version="1.0" encoding="UTF-8"?>
    <mc:messageContainer xmlns:sit="http://datex2.eu/schema/3/situation" xmlns:loc="http://datex2.eu/schema/3/locationReferencing" xmlns:com="http://datex2.eu/schema/3/common" xmlns:mc="http://datex2.eu/schema/3/messageContainer">
      <mc:payload xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="sit:SituationPublication">
        <sit:situation id="S1">
          <sit:situationRecord xsi:type="sit:VehicleObstruction" id="R1" version="1">
            <sit:validity>
              <com:validityStatus>definedByValidityTimeSpec</com:validityStatus>
              <com:validityTimeSpecification>
                <com:overallStartTime>2026-10-15T11:28:01.123456789Z</com:overallStartTime>
              </com:validityTimeSpecification>
            </sit:validity>
            <sit:locationReference>
              <loc:pointByCoordinates>
                <loc:bearing>274</loc:bearing>
                <loc:pointCoordinates><loc:latitude>51.48042</loc:latitude><loc:longitude>3.8973</loc:longitude></loc:pointCoordinates>
              </loc:pointByCoordinates>
            </sit:locationReference>
            <sit:vehicleObstructionType>brokenDownVehicle</sit:vehicleObstructionType>
          </sit:situationRecord>
        </sit:situation>
        <sit:situation id="S2">
          <sit:situationRecord xsi:type="sit:RoadOrCarriagewayOrLaneManagement" id="R2" version="1">
            <sit:validity>
              <com:validityStatus>definedByValidityTimeSpec</com:validityStatus>
              <com:validityTimeSpecification>
                <com:overallStartTime>2026-10-15T08:59:43Z</com:overallStartTime>
                <com:overallEndTime>2026-10-15T15:00:00Z</com:overallEndTime>
              </com:validityTimeSpecification>
            </sit:validity>
            <sit:cause><sit:causeType>roadMaintenance</sit:causeType></sit:cause>
            <sit:locationReference>
              <loc:gmlLineString><loc:posList>51.480654 3.889533 51.480463 3.892717</loc:posList></loc:gmlLineString>
            </sit:locationReference>
            <sit:roadOrCarriagewayOrLaneManagementType>laneClosures</sit:roadOrCarriagewayOrLaneManagementType>
          </sit:situationRecord>
        </sit:situation>
        <sit:situation id="S3">
          <sit:situationRecord xsi:type="sit:Accident" id="R3" version="1">
            <sit:accidentType>accident</sit:accidentType>
          </sit:situationRecord>
        </sit:situation>
      </mc:payload>
    </mc:messageContainer>
    """

    func testParsesPointRecord() throws {
        let incidents = try XCTUnwrap(NDWSituationParser.parse(Data(feed.utf8)))
        let breakdown = try XCTUnwrap(incidents.first { $0.id == "R1" })

        XCTAssertEqual(breakdown.kind, .brokenDownVehicle)
        XCTAssertFalse(breakdown.isPlanned)
        XCTAssertEqual(breakdown.bearing, 274)
        XCTAssertEqual(breakdown.points.count, 1)
        XCTAssertEqual(breakdown.points[0].latitude, 51.48042, accuracy: 0.000001)
        XCTAssertEqual(breakdown.points[0].longitude, 3.8973, accuracy: 0.000001)
        XCTAssertEqual(breakdown.startTime, ISO8601DateFormatter().date(from: "2026-10-15T11:28:01Z"))
    }

    func testParsesLineRecordAsPlannedLaneClosure() throws {
        let incidents = try XCTUnwrap(NDWSituationParser.parse(Data(feed.utf8)))
        let works = try XCTUnwrap(incidents.first { $0.id == "R2" })

        XCTAssertEqual(works.kind, .laneClosure)
        XCTAssertTrue(works.isPlanned)
        XCTAssertEqual(works.points.count, 2)
        XCTAssertEqual(works.endTime, ISO8601DateFormatter().date(from: "2026-10-15T15:00:00Z"))
    }

    func testSkipsRecordsWithoutCoordinates() throws {
        let incidents = try XCTUnwrap(NDWSituationParser.parse(Data(feed.utf8)))
        XCTAssertEqual(incidents.map(\.id), ["R1", "R2"])
    }

    func testReturnsNilForInvalidXML() {
        XCTAssertNil(NDWSituationParser.parse(Data("<niet-af".utf8)))
    }

    func testKindMapping() {
        XCTAssertEqual(TrafficIncident.kind(recordType: "Accident", details: []), .accident)
        XCTAssertEqual(TrafficIncident.kind(recordType: "VehicleObstruction", details: ["other"]), .stationaryVehicle)
        XCTAssertEqual(TrafficIncident.kind(recordType: "GeneralObstruction", details: ["other"]), .obstruction)
        XCTAssertEqual(TrafficIncident.kind(recordType: "GeneralNetworkManagement", details: ["bridgeSwingInOperation"]), .bridgeOpening)
        XCTAssertEqual(TrafficIncident.kind(recordType: "RoadOrCarriagewayOrLaneManagement", details: ["roadClosed"]), .closure)
        XCTAssertEqual(TrafficIncident.kind(recordType: "RoadOrCarriagewayOrLaneManagement", details: ["other", "roadMaintenance"]), .roadworks)
        XCTAssertEqual(TrafficIncident.kind(recordType: "Onbekend", details: []), .other)
    }
}

final class RouteIncidentMatcherTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Rechte route van ~5,5 km pal naar het noorden.
    private let route = [
        CLLocationCoordinate2D(latitude: 51.50, longitude: 3.90),
        CLLocationCoordinate2D(latitude: 51.525, longitude: 3.90),
        CLLocationCoordinate2D(latitude: 51.55, longitude: 3.90),
    ]

    func testIncidentOnRouteMatches() {
        let accident = incident("ongeval", kind: .accident, latitude: 51.52, longitude: 3.901) // ~70 m naast de route
        XCTAssertEqual(ids(matching: [accident]), ["ongeval"])
    }

    func testIncidentFarFromRouteDoesNotMatch() {
        let elsewhere = incident("elders", kind: .accident, latitude: 51.52, longitude: 3.92) // ~1,4 km
        XCTAssertEqual(ids(matching: [elsewhere]), [])
    }

    func testIncidentBeyondRouteEndDoesNotMatch() {
        let beyond = incident("voorbij", kind: .accident, latitude: 51.56, longitude: 3.90) // ~1,1 km na het eind
        XCTAssertEqual(ids(matching: [beyond]), [])
    }

    func testOppositeDirectionDoesNotMatch() {
        let northbound = incident("noord", kind: .stationaryVehicle, latitude: 51.52, longitude: 3.90, bearing: 10)
        let southbound = incident("zuid", kind: .stationaryVehicle, latitude: 51.52, longitude: 3.90, bearing: 185)
        XCTAssertEqual(ids(matching: [northbound, southbound]), ["noord"])
    }

    func testOldPlannedWorkDoesNotExplainDelay() {
        let old = incident("oud", kind: .roadworks, planned: true, latitude: 51.52, longitude: 3.90, startedAgo: 3 * 3600)
        let fresh = incident("vers", kind: .bridgeOpening, planned: true, latitude: 51.53, longitude: 3.90, startedAgo: 600)
        XCTAssertEqual(ids(matching: [old, fresh]), ["vers"])
    }

    func testEndedIncidentDoesNotMatch() {
        let ended = TrafficIncident(
            id: "voorbij", kind: .accident, isPlanned: false,
            points: [CLLocationCoordinate2D(latitude: 51.52, longitude: 3.90)],
            bearing: nil, startTime: now.addingTimeInterval(-3600), endTime: now.addingTimeInterval(-60)
        )
        XCTAssertEqual(ids(matching: [ended]), [])
    }

    func testUnplannedComeFirstThenNewest() {
        let bridge = incident("brug", kind: .bridgeOpening, planned: true, latitude: 51.51, longitude: 3.90, startedAgo: 60)
        let olderAccident = incident("ongeval", kind: .accident, latitude: 51.52, longitude: 3.90, startedAgo: 1800)
        let newerBreakdown = incident("pech", kind: .brokenDownVehicle, latitude: 51.53, longitude: 3.90, startedAgo: 300)
        XCTAssertEqual(ids(matching: [bridge, olderAccident, newerBreakdown]), ["pech", "ongeval", "brug"])
    }

    func testRouteWithoutSegmentsMatchesNothing() {
        let accident = incident("ongeval", kind: .accident, latitude: 51.50, longitude: 3.90)
        XCTAssertTrue(RouteIncidentMatcher.incidents(along: [route[0]], in: [accident], now: now).isEmpty)
    }

    func testAngularDifferenceWrapsAround() {
        XCTAssertEqual(RouteIncidentMatcher.angularDifference(350, 10), 20)
        XCTAssertEqual(RouteIncidentMatcher.angularDifference(90, 270), 180)
    }

    private func incident(
        _ id: String,
        kind: TrafficIncident.Kind,
        planned: Bool = false,
        latitude: Double,
        longitude: Double,
        bearing: Double? = nil,
        startedAgo: TimeInterval = 600
    ) -> TrafficIncident {
        TrafficIncident(
            id: id, kind: kind, isPlanned: planned,
            points: [CLLocationCoordinate2D(latitude: latitude, longitude: longitude)],
            bearing: bearing, startTime: now.addingTimeInterval(-startedAgo), endTime: nil
        )
    }

    private func ids(matching incidents: [TrafficIncident]) -> [String] {
        RouteIncidentMatcher.incidents(along: route, in: incidents, now: now).map(\.id)
    }
}

final class DelayCauseTextTests: XCTestCase {
    private let incident = TrafficIncident(
        id: "1", kind: .accident, isPlanned: false,
        points: [CLLocationCoordinate2D(latitude: 51.6, longitude: 3.9)],
        bearing: nil, startTime: Date(timeIntervalSince1970: 0), endTime: nil
    )

    func testDescribesIncidentWithPlaceAndTime() {
        let text = DelayCauseText.text(for: incident, place: "Zeelandbrug, Zierikzee", otherCount: 0) { _ in "13:05" }
        XCTAssertEqual(text, "Ongeval bij Zeelandbrug, Zierikzee (sinds 13:05)")
    }

    func testFallsBackToRouteWithoutPlaceAndMentionsOthers() {
        XCTAssertEqual(
            DelayCauseText.text(for: incident, place: nil, otherCount: 1) { _ in "13:05" },
            "Ongeval op je route (sinds 13:05), plus 1 andere melding"
        )
        XCTAssertEqual(
            DelayCauseText.text(for: incident, place: nil, otherCount: 3) { _ in "13:05" },
            "Ongeval op je route (sinds 13:05), plus 3 andere meldingen"
        )
    }
}
