import XCTest
@testable import MeetScribe

final class MeetingLinkParserTests: XCTestCase {
    func testExtractsGoogleMeetLinkFromNotes() throws {
        let text = "Join the meeting here: https://meet.google.com/abc-defg-hij"

        let url = try XCTUnwrap(MeetingLinkParser.extractMeetingURL(from: text))

        XCTAssertEqual(url.absoluteString, "https://meet.google.com/abc-defg-hij")
    }

    func testExtractsZoomLinkFromLocationWithoutScheme() throws {
        let text = "zoom.us/j/123456789?pwd=abc123"

        let url = try XCTUnwrap(MeetingLinkParser.extractMeetingURL(from: text))

        XCTAssertEqual(url.absoluteString, "https://zoom.us/j/123456789?pwd=abc123")
    }

    func testExtractsTeamsLinkFromRawText() throws {
        let text = "Microsoft Teams link: https://teams.microsoft.com/l/meetup-join/19%3ameeting_id"

        let url = try XCTUnwrap(MeetingLinkParser.extractMeetingURL(from: text))

        XCTAssertEqual(url.absoluteString, "https://teams.microsoft.com/l/meetup-join/19%3ameeting_id")
    }

    func testReturnsNilWhenNoMeetingLinkExists() {
        let text = "Plain event notes without a meeting link."

        XCTAssertNil(MeetingLinkParser.extractMeetingURL(from: text))
    }
}
