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

final class ChatTests: XCTestCase {
    func testRoomsAndTitles() throws {
        let json = #"{"rooms":[{"id":"r1","name":"flood-response-2026","kind":"channel","unread":3,"state":"join","federated":true},{"id":"r2","name":"","kind":"direct","unread":0,"with":["@u2:ministry.example"]}],"people":{"@u2:ministry.example":{"name":"Anna Kowalska","local":true}},"me":"@u1:ministry.example"}"#
        let rooms = try JSONDecoder().decode(Rooms.self, from: Data(json.utf8))
        XCTAssertEqual("# flood-response-2026", rooms.title(rooms.rooms[0]))
        XCTAssertEqual("Anna Kowalska", rooms.title(rooms.rooms[1]))
    }
}
