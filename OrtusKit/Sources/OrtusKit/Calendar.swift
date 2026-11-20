// One's events, repeats expanded, as the calendar app answers them.
import Foundation

public struct Attendee: Decodable, Equatable {
    public let email: String
    public let name: String?
    public let answer: String?
}

public struct Event: Decodable, Equatable, Identifiable {
    public let id: String
    public let summary: String
    public let start: Int64
    public let end: Int64
    public let allDay: Bool?
    public let location: String?
    public let organizer: String?
    public let attendees: [Attendee]?
    public let answer: String?
    public let mine: Bool?
    public let calendar: String?

    public var startDate: Date { Date(timeIntervalSince1970: Double(start) / 1000) }
    public var endDate: Date { Date(timeIntervalSince1970: Double(end) / 1000) }
    /// An invitation still waiting for one's answer.
    public var waiting: Bool { mine != true && answer == "NEEDS-ACTION" }
}

extension Client {
    /// Events between two times (at most 62 days apart).
    public func events(from: Date, to: Date) async throws -> [Event] {
        struct Answer: Decodable { let events: [Event] }
        let ms = { (d: Date) in Int64(d.timeIntervalSince1970 * 1000) }
        let a: Answer = try await call("GET", "/calendar/events?from=\(ms(from))&to=\(ms(to))")
        return a.events.sorted { $0.start < $1.start }
    }

    public func answer(_ event: Event, _ answer: String) async throws {
        struct Ignored: Decodable {}
        let _: Ignored = try await call("POST", "/calendar/events/\(event.id)/rsvp", json: ["answer": answer])
    }
}
