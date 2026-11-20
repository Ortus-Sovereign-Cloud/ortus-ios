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
