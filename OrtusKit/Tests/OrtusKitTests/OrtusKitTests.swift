import XCTest
@testable import OrtusKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class EncodingTests: XCTestCase {
    func testSHA256() {
        XCTAssertEqual(SHA256.hash(Data("abc".utf8)).map { String(format: "%02x", $0) }.joined(),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(SHA256.hash(Data()).map { String(format: "%02x", $0) }.joined(),
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        // Longer than one block.
        let long = Data(repeating: 0x61, count: 1000)
        XCTAssertEqual(SHA256.hash(long).map { String(format: "%02x", $0) }.joined(),
                       "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3")
    }

    func testBase64URL() {
        let d = Data([0xfb, 0xff, 0x00])
        XCTAssertEqual("-_8A", d.base64URL)
        XCTAssertEqual(d, Data(base64URL: "-_8A"))
    }

    func testCBOR() {
        XCTAssertEqual(Data([0x18, 0x64]), CBOR.unsigned(100).encoded)
        XCTAssertEqual(Data([0x26]), CBOR.negative(-7).encoded)
        XCTAssertEqual(Data([0x63, 0x66, 0x6d, 0x74]), CBOR.text("fmt").encoded)
        XCTAssertEqual(Data([0xa0]), CBOR.map([]).encoded)
    }

    func testRegistrationLayout() {
        let point = Data([4] + [UInt8](repeating: 1, count: 32) + [UInt8](repeating: 2, count: 32))
        let id = Data(repeating: 9, count: 16)
        let auth = WebAuthn.registrationData(rpID: "ortus.example", credentialID: id, publicKey: point)
        XCTAssertEqual(SHA256.hash(Data("ortus.example".utf8)), auth.prefix(32))
        XCTAssertEqual(0x45, auth[32]) // user present, verified, attested
        XCTAssertEqual(id, auth.subdata(in: 55..<71))
        let object = WebAuthn.attestationObject(authData: auth)
        XCTAssertEqual(0xa3, object.first) // a map of three
        XCTAssertEqual("ortus.example", WebAuthn.rpID(publicURL: "https://ortus.example:8443"))
        XCTAssertEqual("https://ortus.example", WebAuthn.origin(publicURL: "https://ortus.example/"))
    }

    func testClientData() throws {
        let data = WebAuthn.clientData(type: "webauthn.get", challenge: "abc", origin: "https://ortus.example")
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual("webauthn.get", json["type"] as? String)
        XCTAssertEqual("https://ortus.example", json["origin"] as? String)
    }
}

struct Recorded: Transport {
    let status: Int
    let body: String
    let seen: Box
    final class Box: @unchecked Sendable { var requests: [URLRequest] = [] }
    func send(_ request: URLRequest) async throws -> (Int, Data) {
        seen.requests.append(request)
        return (status, Data(body.utf8))
    }
}

final class ClientTests: XCTestCase {
    func testServerAddress() {
        XCTAssertEqual("https://ortus.example", Client.serverURL(from: " ortus.example/ ")?.absoluteString)
        XCTAssertEqual("http://127.0.0.1:8080", Client.serverURL(from: "http://127.0.0.1:8080")?.absoluteString)
        XCTAssertNil(Client.serverURL(from: "ftp://x"))
        XCTAssertNil(Client.serverURL(from: ""))
    }

    func testHeadersAndErrors() async throws {
        let box = Recorded.Box()
        let ok = Client(server: URL(string: "https://ortus.example")!, token: "t1", transport: Recorded(status: 200, body: #"{"id":"u1","email":"a@b","name":"A","role":"member"}"#, seen: box))
        let me: Me = try await ok.call("GET", "/me")
        XCTAssertEqual("u1", me.id)
        let r = box.requests[0]
        XCTAssertEqual("https://ortus.example/api/v1/me", r.url?.absoluteString)
        XCTAssertEqual("Bearer t1", r.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(r.value(forHTTPHeaderField: "X-Requested-With"))
        let failing = Client(server: URL(string: "https://ortus.example")!, transport: Recorded(status: 403, body: #"{"error":{"code":"forbidden","message":"Not yours."}}"#, seen: box))
        do {
            let _: Me = try await failing.call("POST", "/x", json: ["a": 1])
            XCTFail("an error")
        } catch let e as APIError {
            XCTAssertEqual(APIError(status: 403, code: "forbidden", message: "Not yours."), e)
        }
        XCTAssertEqual("ortus", box.requests[1].value(forHTTPHeaderField: "X-Requested-With"))
    }
}

final class MailTests: XCTestCase {
    func testInboxAsksAndReads() async throws {
        let box = Recorded.Box()
        let body = #"{"methodResponses":[["Mailbox/get",{"list":[{"id":"mb1","name":"Inbox","role":"inbox","unreadEmails":3}]},"b"]]}"#
        let client = Client(server: URL(string: "https://ortus.example")!, token: "t", transport: Recorded(status: 200, body: body, seen: box))
        // The second answer lacks the lists: nothing breaks, nothing shown.
        let got = try await client.inbox(.important)
        XCTAssertEqual([], got.emails)
        let sent = try JSONSerialization.jsonObject(with: box.requests[1].httpBody!) as! [String: Any]
        let calls = sent["methodCalls"] as! [[Any]]
        XCTAssertEqual("Email/query", calls[0][0] as? String)
        XCTAssertEqual("https://ortus.example/api/v1/mail/web/jmap", box.requests[1].url?.absoluteString)
    }

    func testEmailDecodes() throws {
        let json = #"[{"id":"m1","threadId":"t1","subject":"Gauge report","from":[{"name":"Anna Kowalska","email":"anna@regional.example"}],"receivedAt":"2026-11-20T10:42:00Z","preview":"Attached","keywords":{"$seen":true},"ortusInvite":{"uid":"u","method":"REQUEST","summary":"Review","start":1795784400000,"end":1795786200000,"answer":"NEEDS-ACTION","cancelled":false,"inCalendar":true,"organizer":null}}]"#
        let emails = try JMAP.decode(try JSONSerialization.jsonObject(with: Data(json.utf8)), as: [Email].self)
        XCTAssertEqual("Anna Kowalska", emails[0].sender)
        XCTAssertFalse(emails[0].unread)
        XCTAssertEqual("NEEDS-ACTION", emails[0].ortusInvite?.answer)
        XCTAssertNotNil(emails[0].date)
    }

    func testMethodErrors() {
        XCTAssertThrowsError(try JMAP.answers(Data(#"{"methodResponses":[["error",{"type":"forbidden"},"x"]]}"#.utf8)))
    }
}

final class DeliveryTests: XCTestCase {
    private func email(_ delivery: String) throws -> Email {
        try JMAP.decode(try JSONSerialization.jsonObject(with: Data(#"[{"id":"m1","threadId":"t1","subject":"Agreement","to":[{"name":"Anna Kowalska","email":"anna@regional.example"},{"name":null,"email":"kasia@down.example"}],"receivedAt":"2026-11-22T10:00:00Z","keywords":{"$seen":true},"ortusDelivery":\#(delivery)}]"#.utf8)), as: [Email].self)[0]
    }

    func testSentShowsWhomAndHowDeliveryGoes() throws {
        let delivered = try email(#"[{"recipient":"anna@regional.example","state":"sent","attempts":1,"lastError":null}]"#)
        XCTAssertEqual("Anna Kowalska, kasia@down.example", delivered.recipients)
        XCTAssertNil(delivered.deliveryState)
        XCTAssertEqual("trying", try email(#"[{"recipient":"kasia@down.example","state":"deferred","attempts":3,"lastError":"no answer"}]"#).deliveryState)
        XCTAssertEqual("failed", try email(#"[{"recipient":"a","state":"deferred"},{"recipient":"b","state":"bounced"}]"#).deliveryState)
        XCTAssertNil(try email("[]").deliveryState)
        XCTAssertNil(try email("null").deliveryState, "received mail has none")
    }
}

final class ChatTests: XCTestCase {
    func testRoomsAndTitles() throws {
        let json = #"{"rooms":[{"id":"r1","name":"flood-response-2026","kind":"channel","unread":3,"state":"join","federated":true},{"id":"r2","name":"","kind":"direct","unread":0,"with":["@u2:ministry.example"]}],"people":{"@u2:ministry.example":{"name":"Anna Kowalska","local":true}},"me":"@u1:ministry.example"}"#
        let rooms = try JSONDecoder().decode(Rooms.self, from: Data(json.utf8))
        XCTAssertEqual("# flood-response-2026", rooms.title(rooms.rooms[0]))
        XCTAssertEqual("Anna Kowalska", rooms.title(rooms.rooms[1]))
    }
}

/// Answers each request in turn with the next body (shaped like the
/// installation's real answers), and keeps the requests.
struct Scripted: Transport {
    let bodies: [String]
    let seen: Recorded.Box
    func send(_ request: URLRequest) async throws -> (Int, Data) {
        seen.requests.append(request)
        let i = min(seen.requests.count - 1, bodies.count - 1)
        return (200, Data(bodies[i].utf8))
    }
}

final class AnswersTests: XCTestCase {
    func testInboxListsAndCounts() async throws {
        let box = Recorded.Box()
        let boxes = #"{"methodResponses":[["Mailbox/get",{"list":[{"id":"mb1","name":"Inbox","role":"inbox","unreadEmails":3}]},"b"]]}"#
        let lists = #"{"methodResponses":[["Email/query",{"ids":["m1"]},"q"],["Email/get",{"list":[{"id":"m1","threadId":"t1","subject":"Gauge report","from":[{"name":"Anna Kowalska","email":"anna@regional.example"}],"receivedAt":"2026-11-20T10:42:00Z","preview":"Attached","keywords":{}}]},"l"],["Email/query",{"total":2,"ids":[]},"u-important"],["Email/query",{"total":0,"ids":[]},"u-other"],["Email/query",{"total":5,"ids":[]},"u-feeds"]]}"#
        let client = Client(server: URL(string: "https://ortus.example")!, token: "t", transport: Scripted(bodies: [boxes, lists], seen: box))
        let got = try await client.inbox(.important)
        XCTAssertEqual(["Gauge report"], got.emails.map(\.subject))
        XCTAssertTrue(got.emails[0].unread)
        XCTAssertEqual(2, got.unread[.important])
        XCTAssertEqual(5, got.unread[.feeds])
    }

    func testRSVPTakesTheRealAnswer() async throws {
        let box = Recorded.Box()
        // As ortus-mail answers: numbers and a bool beside strings.
        let answer = #"{"uid":"u1","method":"REQUEST","summary":"Logistics stand-up","start":1795784400000,"end":1795786200000,"answer":"ACCEPTED","cancelled":false,"inCalendar":true,"organizer":"marek@ministry.example"}"#
        let client = Client(server: URL(string: "https://ortus.example")!, token: "t", transport: Scripted(bodies: [answer], seen: box))
        let email = try JMAP.decode(try JSONSerialization.jsonObject(with: Data(#"[{"id":"m1","threadId":"t1","subject":"Logistics stand-up","from":[{"name":"Marek","email":"marek@ministry.example"}],"receivedAt":"2026-11-20T10:42:00Z","preview":"","keywords":{}}]"#.utf8)), as: [Email].self)[0]
        try await client.rsvp(email, answer: "accepted")
        let sent = try JSONSerialization.jsonObject(with: box.requests[0].httpBody!) as! [String: Any]
        XCTAssertEqual("accepted", sent["answer"] as? String)
    }

    func testNoticesReadAll() async throws {
        let box = Recorded.Box()
        let client = Client(server: URL(string: "https://ortus.example")!, token: "t", transport: Scripted(bodies: [#"{"unread":0}"#], seen: box))
        try await client.markNoticesRead()
        let sent = try JSONSerialization.jsonObject(with: box.requests[0].httpBody!) as! [String: Any]
        XCTAssertEqual(true, sent["all"] as? Bool)
    }

    func testTheBellCountsAsTheWebDoes() async throws {
        let box = Recorded.Box()
        let listing = #"{"items":[],"unread":3,"counts":{"mention":1,"approval":2,"alert":0,"update":0},"quiet":{"from":null,"to":null,"dnd":false}}"#
        let client = Client(server: URL(string: "https://ortus.example")!, token: "t", transport: Scripted(bodies: [listing], seen: box))
        let unread = try await client.unreadNotices()
        XCTAssertEqual(3, unread)
        XCTAssertEqual("/api/v1/notifications", box.requests[0].url?.path)
    }

    func testSearchResultsOpenTheirPlace() async throws {
        let box = Recorded.Box()
        // As core answers: each app's own meta, with where it opens.
        let results = #"{"results":[{"app":"mail","id":"m1","title":"Gauge report","snippet":"Attached","meta":{"path":"/mail?thread=t1","from":"Anna Kowalska","attachment":false},"at":1,"mine":true},{"app":"calendar","id":"e1","title":"Stand-up","snippet":"","meta":{"path":"/calendar?event=e1","start":1795784400000},"at":2,"mine":true},{"app":"people","id":"p1","title":"Anna","snippet":""}],"words":["gauge"]}"#
        let client = Client(server: URL(string: "https://ortus.example")!, token: "t", transport: Scripted(bodies: [results], seen: box))
        let hits = try await client.search("gauge")
        XCTAssertEqual([.thread("t1"), .event("e1", start: 1795784400000), .web("/people")], hits.map(\.place))
        XCTAssertEqual(1795784400000, hits[1].meta?.start)
    }

    func testPlacesOfWebPaths() {
        XCTAssertEqual(.thread("t1"), Place(path: "/mail?thread=t1"))
        XCTAssertEqual(.room("!r1:ortus.example"), Place(path: "/chat?room=!r1:ortus.example&message=$e1"))
        XCTAssertEqual(.doc("d1"), Place(path: "/docs?doc=d1"))
        XCTAssertEqual(.folder("f1"), Place(path: "/drive?folder=f1"))
        XCTAssertEqual(.file("f2"), Place(path: "/drive?file=f2"))
        XCTAssertEqual(.web("/tasks?task=k1"), Place(path: "/tasks?task=k1"))
        XCTAssertEqual(.approvals, Place(path: "/docs?review=r1"))
        // An event without its start (a notification's) is the web's.
        XCTAssertEqual(.web("/calendar?event=e1"), Place(path: "/calendar?event=e1"))
        XCTAssertEqual(.web("/mail"), Place(path: "/mail"))
        let server = URL(string: "https://ortus.example")!
        XCTAssertEqual("https://ortus.example/tasks?task=k1", Place(path: "/tasks?task=k1").webURL(on: server)?.absoluteString)
        // Only a page of the installation itself.
        XCTAssertNil(Place(path: "//evil.example/x").webURL(on: server))
        XCTAssertNil(Place(path: "https://evil.example/x").webURL(on: server))
        XCTAssertNil(Place(path: "/mail?thread=t1").webURL(on: server))
    }

    func testOriginsAndRelyingParty() throws {
        // As the installation's public_url reads: lower case, no default port, no path.
        XCTAssertEqual("https://ortus.example", Client.serverURL(from: "HTTPS://Ortus.Example:443/inbox")?.absoluteString)
        XCTAssertEqual("http://10.0.2.2:7878", WebAuthn.origin(publicURL: "http://10.0.2.2:7878/"))
        XCTAssertEqual("example.org", try WebAuthn.checkedRPID("example.org", publicURL: "https://ortus.example.org"))
        XCTAssertEqual("ortus.example.org", try WebAuthn.checkedRPID(nil, publicURL: "https://Ortus.example.org"))
        XCTAssertThrowsError(try WebAuthn.checkedRPID("bank.example", publicURL: "https://ortus.example.org"))
        XCTAssertThrowsError(try WebAuthn.checkedRPID("ple.org", publicURL: "https://ortus.example.org"))
    }
}

final class InvitationLinkTests: XCTestCase {
    let code = "GrZQMSTSLFQ-bZjJLte7CE2wAbAZye7iS0osZU1a8os"

    func testTheAppsOwnLink() {
        let link = InvitationLink.parse("ortus://join?server=https%3A%2F%2FOrtus.cc&code=\(code)")
        XCTAssertEqual(InvitationLink(server: "https://ortus.cc", code: code), link)
        // A test installation on a port, over plain HTTP.
        XCTAssertEqual("http://127.0.0.1:7900", InvitationLink.parse("ortus://join?server=http%3A%2F%2F127.0.0.1%3A7900&code=\(code)")?.server)
    }

    func testAnInvitationLinkOrItsQRCode() {
        XCTAssertEqual(InvitationLink(server: "https://ortus.cc", code: code),
                       InvitationLink.parse("  https://ortus.cc/welcome/accept#\(code)\n"))
        XCTAssertEqual("https://work.ministry.example:8443",
                       InvitationLink.parse("https://work.ministry.example:8443/welcome/accept#\(code)")?.server)
    }

    func testTheSharedAppLink() {
        XCTAssertEqual(InvitationLink(server: "https://work.ministry.gov:8443", code: code),
                       InvitationLink.parse("https://join.ortus.cc/i#s=https%3A%2F%2Fwork.ministry.gov%3A8443&c=\(code)"))
        XCTAssertNil(InvitationLink.parse("https://join.ortus.cc/i#s=ftp%3A%2F%2Fx&c=\(code)"))
        XCTAssertNil(InvitationLink.parse("https://join.ortus.cc/i#c=\(code)"))
    }

    func testAPhoneSignInCode() {
        let phone = InvitationLink(server: "https://ortus.cc", code: code, kind: .phone)
        // The QR code on the web ("Sign in on your phone"), and the button on a phone.
        XCTAssertEqual(phone, InvitationLink.parse("https://join.ortus.cc/i#s=https%3A%2F%2Fortus.cc&p=\(code)"))
        XCTAssertEqual(phone, InvitationLink.parse("ortus://signin?server=https%3A%2F%2Fortus.cc&code=\(code)"))
        // An invitation stays one.
        XCTAssertEqual(.invite, InvitationLink.parse("https://join.ortus.cc/i#s=https%3A%2F%2Fortus.cc&c=\(code)")?.kind)
        XCTAssertNil(InvitationLink.parse("https://join.ortus.cc/i#s=https%3A%2F%2Fortus.cc&p=short"))
    }

    func testAnythingElseIsNot() {
        for text in [
            "",
            "https://ortus.cc/welcome/accept",            // no code
            "https://ortus.cc/sign-in#\(code)",            // another page
            "https://ortus.cc/welcome/accept#short",       // not a code
            "https://ortus.cc/welcome/accept#\(code)<script>",
            "ortus://join?code=\(code)",                   // no installation
            "ortus://join?server=ftp%3A%2F%2Fx&code=\(code)",
            "ortus://other?server=https%3A%2F%2Fortus.cc&code=\(code)",
            "mailto:someone@ortus.cc",
        ] {
            XCTAssertNil(InvitationLink.parse(text), text)
        }
    }
}

final class DiscoveryTests: XCTestCase {
    func testWhereToAsk() {
        XCTAssertEqual(["https://ministry.gov/.well-known/ortus", "https://ortus.ministry.gov/.well-known/ortus"],
                       Discovery.candidates(for: " Olena@Ministry.gov ").map(\.absoluteString))
        XCTAssertEqual([], Discovery.candidates(for: "not an address"))
        XCTAssertEqual([], Discovery.candidates(for: "a@b"))
        XCTAssertEqual([], Discovery.candidates(for: "a@evil.example/x"))
    }

    func testTheAnswer() {
        XCTAssertEqual("https://work.ministry.gov", Discovery.server(fromAnswer: Data(#"{"server":"https://Work.Ministry.gov/"}"#.utf8))?.absoluteString)
        XCTAssertNil(Discovery.server(fromAnswer: Data(#"{"server":"http://work.ministry.gov"}"#.utf8)), "https only")
        XCTAssertNil(Discovery.server(fromAnswer: Data("<html>".utf8)))
    }
}

final class PushTests: XCTestCase {
    func testRegistersWithTheDeviceTokenInHex() async throws {
        let seen = Recorded.Box()
        let client = Client(server: URL(string: "https://ortus.example")!, token: "s1", transport: Recorded(status: 200, body: #"{"id":"pd1","fetch_token":"f1"}"#, seen: seen))
        let r = try await client.registerPush(token: Data([0x0a, 0xff, 0x10]), sandbox: false, utcOffsetMinutes: 60)
        XCTAssertEqual(PushRegistration(id: "pd1", fetch_token: "f1"), r)
        let sent = try JSONSerialization.jsonObject(with: seen.requests[0].httpBody!) as! [String: Any]
        XCTAssertEqual("0aff10", sent["token"] as? String)
        XCTAssertEqual("production", sent["environment"] as? String)
        XCTAssertEqual("apns", sent["platform"] as? String)
        XCTAssertEqual("https://ortus.example/api/v1/me/push-devices", seen.requests[0].url?.absoluteString)
    }

    func testFetchesWithTheFetchTokenOnly() async throws {
        let seen = Recorded.Box()
        let notice = try await Push.fetch(server: URL(string: "https://ortus.example")!, fetchToken: "f1", id: "nabc", transport: Recorded(status: 200, body: #"{"app":"mail","title":"Ana Ferreira","detail":"Town hall","path":"/mail?thread=t1","at":1}"#, seen: seen))
        XCTAssertEqual("Ana Ferreira", notice.title)
        let r = seen.requests[0]
        XCTAssertEqual("https://ortus.example/api/v1/push/notices/nabc", r.url?.absoluteString)
        XCTAssertEqual("f1", r.value(forHTTPHeaderField: "X-Ortus-Push"))
        XCTAssertNil(r.value(forHTTPHeaderField: "Authorization"), "never the session")
        do {
            _ = try await Push.fetch(server: URL(string: "https://ortus.example")!, fetchToken: "f1", id: "x", transport: Recorded(status: 401, body: "{}", seen: seen))
            XCTFail("a refused fetch throws")
        } catch {}
    }

    func testReadsOnlyOurPushes() {
        XCTAssertEqual("n1", Push.parts(of: ["n": "n1", "s": "https://ortus.example"])?.id)
        XCTAssertEqual("https://ortus.example", Push.parts(of: ["n": "n1", "s": "https://ortus.example"])?.server.absoluteString)
        XCTAssertNil(Push.parts(of: ["n": "n1"]))
        XCTAssertNil(Push.parts(of: ["s": "https://ortus.example"]))
        XCTAssertNil(Push.parts(of: ["n": "n1", "s": "https://ortus.example/elsewhere"]))
    }

    func testCallRooms() {
        XCTAssertEqual("r1", Push.callRoom("/calls?room=r1"))
        XCTAssertEqual("r 2", Push.callRoom("/calls?room=r%202&x=1"))
        XCTAssertNil(Push.callRoom("/chat?room=r1"))
        XCTAssertNil(Push.callRoom(nil))
    }

    func testOpensTheRightTab() {
        XCTAssertEqual(0, Push.tab(for: "/mail?thread=t1"))
        XCTAssertEqual(1, Push.tab(for: "/chat?room=r1"))
        XCTAssertEqual(2, Push.tab(for: "/calendar"))
        XCTAssertEqual(3, Push.tab(for: "/drive"))
        XCTAssertEqual(4, Push.tab(for: "/approvals"))
        XCTAssertEqual(4, Push.tab(for: nil))
    }
}

final class CacheTests: XCTestCase {
    struct Flaky: Transport {
        let box: Box
        final class Box: @unchecked Sendable { var online = true; var calls = 0 }
        func send(_ request: URLRequest) async throws -> (Int, Data) {
            box.calls += 1
            guard box.online else { throw URLError(.notConnectedToInternet) }
            return (200, Data("{\"n\":\(box.calls)}".utf8))
        }
    }

    private func dir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ortus-cache-\(UUID().uuidString)")
    }

    func testReadsAreKeptAndServedOffline() async throws {
        let box = Flaky.Box()
        let seen = Recorded.Box()
        _ = seen
        let reached = ReachedBox()
        let t = CachingTransport(inner: Flaky(box: box), cache: ResponseCache(directory: dir())) { reached.last = $0 }
        let client = Client(server: URL(string: "https://ortus.example")!, token: "s", transport: t)
        struct N: Decodable { let n: Int }
        let first: N = try await client.call("GET", "/chat/rooms")
        XCTAssertEqual(1, first.n)
        XCTAssertEqual(true, reached.last)
        box.online = false
        let offline: N = try await client.call("GET", "/chat/rooms")
        XCTAssertEqual(1, offline.n, "the kept answer")
        XCTAssertEqual(false, reached.last)
        // Never fetched: no answer.
        do {
            let _: N = try await client.call("GET", "/calendar/events")
            XCTFail("nothing kept")
        } catch {}
        // Writes are never answered from the phone.
        do {
            let _: N = try await client.call("POST", "/chat/rooms/r1/messages", json: ["text": "hi"])
            XCTFail("a write needs the connection")
        } catch {}
        // Shown at once: from the phone only, without asking the installation.
        box.online = true
        let calls = box.calls
        let quick: N = try await CachingTransport.$cacheOnly.withValue(true) { try await client.call("GET", "/chat/rooms") }
        XCTAssertEqual(1, quick.n)
        XCTAssertEqual(calls, box.calls)
        t.cache.clear()
        box.online = false
        do {
            let _: N = try await client.call("GET", "/chat/rooms")
            XCTFail("cleared")
        } catch {}
    }

    func testOnlyJmapReadsCount() throws {
        func jmap(_ names: [String]) -> URLRequest {
            var r = URLRequest(url: URL(string: "https://ortus.example/api/v1/mail/web/jmap")!)
            r.httpMethod = "POST"
            r.httpBody = try! JSONSerialization.data(withJSONObject: ["methodCalls": names.map { [$0, [:], "x"] }])
            return r
        }
        XCTAssertTrue(CachingTransport.reads(jmap(["Mailbox/get", "Email/query", "Email/get"])))
        XCTAssertFalse(CachingTransport.reads(jmap(["Email/get", "Email/set"])))
        XCTAssertFalse(CachingTransport.reads(jmap(["EmailSubmission/set"])))
        var signOut = URLRequest(url: URL(string: "https://ortus.example/api/v1/session/sign-out")!)
        signOut.httpMethod = "POST"
        XCTAssertFalse(CachingTransport.reads(signOut))
    }
}

final class ReachedBox: @unchecked Sendable { var last: Bool? }

final class CallTests: XCTestCase {
    func testPartsRoundTrip() {
        let long = "v=0\r\n" + String(repeating: "a=x", count: 20_000)
        let parts = CallParts.split(long, id: "abc")
        XCTAssertEqual(4, parts.count)
        let j = CallParts.Joiner()
        XCTAssertNil(j.take(parts[2]))
        XCTAssertNil(j.take(parts[0]))
        XCTAssertNil(j.take(parts[3]))
        XCTAssertEqual(long, j.take(parts[1]))
        XCTAssertNil(j.take(#"{"id":"x","part":5,"of":2,"data":"y"}"#))
        XCTAssertEqual("hi", CallParts.Joiner().take(CallParts.split("hi")[0]))
    }

    func testOffersAndAnswers() {
        XCTAssertEqual("v=0", CallParts.offer(#"{"type":"offer","sdp":"v=0","n":3}"#)?.sdp)
        XCTAssertEqual(3, CallParts.offer(#"{"type":"offer","sdp":"v=0","n":3}"#)?.n)
        XCTAssertNil(CallParts.offer(#"{"type":"answer","sdp":"v=0"}"#))
        XCTAssertEqual(#"{"n":3,"sdp":"v=1","type":"answer"}"#, CallParts.answer("v=1", n: 3))
    }

    func testJoinsWithTheRelay() async throws {
        let seen = Recorded.Box()
        let body = #"{"call":{"id":"c1","room":"r1","sessions":[{"session":"s2","user":"u2","muted":true}],"people":{"u2":{"name":"Taras"}}},"session":"s1","ice_servers":[{"urls":["turns:turn.example:443?transport=tcp"],"username":"1:s1","credential":"x"}]}"#
        let client = Client(server: URL(string: "https://ortus.example")!, token: "t", transport: Recorded(status: 200, body: body, seen: seen))
        let j = try await client.joinCall(room: "r1")
        XCTAssertEqual("s1", j.session)
        XCTAssertEqual("turns:turn.example:443?transport=tcp", j.ice_servers?.first?.urls.first)
        XCTAssertEqual("Taras", j.call.name(of: "s2"))
        XCTAssertEqual("https://ortus.example/api/v1/calls/rooms/r1/join", seen.requests[0].url?.absoluteString)
    }

    func testSendsTheOffer() async throws {
        let seen = Recorded.Box()
        let client = Client(server: URL(string: "https://ortus.example")!, token: "t", transport: Recorded(status: 200, body: #"{"answer":{"type":"answer","sdp":"v=0 answer"}}"#, seen: seen))
        let answer = try await client.sendOffer(session: "s1", sdp: "v=0 offer")
        XCTAssertEqual("v=0 answer", answer)
        let sent = try JSONSerialization.jsonObject(with: seen.requests[0].httpBody!) as! [String: Any]
        XCTAssertEqual("v=0 offer", (sent["offer"] as? [String: Any])?["sdp"] as? String)
    }
}

final class OutboxTests: XCTestCase {
    final class Net: Transport, @unchecked Sendable {
        var online = false
        var sent: [URLRequest] = []
        func send(_ request: URLRequest) async throws -> (Int, Data) {
            guard online else { throw URLError(.notConnectedToInternet) }
            sent.append(request)
            return (200, Data("{}".utf8))
        }
    }

    func testMessagesWaitAndGoOnceBackOnline() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ortus-outbox-\(UUID().uuidString)")
        let net = Net()
        let t = CachingTransport(inner: net, cache: ResponseCache(directory: dir.appendingPathComponent("c")))
        t.outbox = Outbox(file: dir.appendingPathComponent("outbox.json"))
        let client = Client(server: URL(string: "https://ortus.example")!, token: "s1", transport: t)
        do {
            try await client.say("On my way", in: "r1")
            XCTFail("queued, not sent")
        } catch let e as APIError {
            XCTAssertEqual("queued", e.code)
        }
        XCTAssertEqual(1, t.outbox?.count)
        // Other writes still fail plainly.
        do {
            struct X: Decodable {}
            let _: X = try await client.call("POST", "/calendar/events", json: [:])
            XCTFail("a write fails offline")
        } catch let e as APIError { XCTFail("not queued: \(e.code)") } catch {}
        XCTAssertEqual(1, t.outbox?.count)
        // Back online: the next call sends what waited, with the session.
        net.online = true
        struct R: Decodable {}
        let _: R = try await client.call("GET", "/chat/rooms")
        for _ in 0..<50 where t.outbox?.count != 0 { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(0, t.outbox?.count)
        let message = net.sent.first { $0.url?.path.hasSuffix("/messages") == true }
        XCTAssertEqual("Bearer s1", message?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(String(decoding: message?.httpBody ?? Data(), as: UTF8.self).contains("On my way"))
        // Nothing of the session was kept on disk.
        XCTAssertFalse((try? String(contentsOf: dir.appendingPathComponent("outbox.json"), encoding: .utf8))?.contains("s1") ?? false)
    }
}


/// End-to-end rooms: nothing in the clear leaves the phone for them.
final class SealedRoomTests: XCTestCase {
    func testASealedRoomNeverGetsAMessageInTheClear() async throws {
        let box = Recorded.Box()
        let rooms = #"{"rooms":[{"id":"r1","name":"plans","kind":"channel","encrypted":true},{"id":"r2","name":"general","kind":"channel"}],"people":{},"me":"@u1:ortus.example"}"#
        let client = Client(server: URL(string: "https://ortus.example")!, token: "t", transport: Scripted(bodies: [rooms, #"{"id":"$e2"}"#], seen: box))
        let got = try await client.rooms()
        XCTAssertEqual("@u1:ortus.example", got.me)
        do {
            try await client.say("the plans", in: "r1")
            XCTFail("a sealed room took a message in the clear")
        } catch let e as SealedRoom {
            XCTAssertEqual("r1", e.room)
        }
        XCTAssertEqual(1, box.requests.count, "nothing was sent")
        try await client.say("hello", in: "r2")
        XCTAssertEqual("https://ortus.example/api/v1/chat/rooms/r2/messages", box.requests.last?.url?.absoluteString)
        do {
            try await client.say("in its thread", in: "r1", thread: "$e0")
            XCTFail("a sealed room's thread took a message in the clear")
        } catch is SealedRoom {}
        try await client.say("in a thread", in: "r2", thread: "$e9")
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: box.requests.last?.httpBody ?? Data()) as? [String: Any])
        XCTAssertEqual("$e9", sent["thread"] as? String)
    }

    func testAThreadIsReadByItsRoot() async throws {
        let box = Recorded.Box()
        let client = Client(server: URL(string: "https://ortus.example")!, token: "t", transport: Recorded(status: 200, body: #"{"messages":[{"id":"$e9","sender":"@u2:o","text":"root","at":1,"replies":2}],"people":{}}"#, seen: box))
        let got = try await client.messages(in: "r2", thread: "$e9")
        XCTAssertEqual("https://ortus.example/api/v1/chat/rooms/r2/messages?thread=%24e9", box.requests.last?.url?.absoluteString)
        XCTAssertEqual(2, got.messages[0].replies)
    }

    func testASealedMessageGoesToTheLibraryWhole() async throws {
        let body = #"{"messages":[{"id":"$e1","sender":"@u2:ortus.example","text":"","at":1,"thread":"$e0","sealed":{"algorithm":"m.megolm.v1.aes-sha2","ciphertext":"AAA","device_id":"D1"}}],"people":{}}"#
        let client = Client(server: URL(string: "https://ortus.example")!, token: "t", transport: Recorded(status: 200, body: body, seen: Recorded.Box()))
        let m = try await client.messages(in: "r1").messages[0]
        let j = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(m.sealedJSON().utf8)) as? [String: Any])
        XCTAssertEqual("$e1", j["id"] as? String)
        XCTAssertEqual("$e0", j["thread"] as? String)
        XCTAssertEqual("AAA", (j["sealed"] as? [String: Any])?["ciphertext"] as? String)
    }
}
