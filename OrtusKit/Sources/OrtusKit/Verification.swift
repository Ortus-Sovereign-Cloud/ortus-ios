// What the phone's verification screens need that does not need a screen:
// a QR code's modules with their quiet zone, and who a device belongs to.

/// A QR code to draw, `width` × `width` modules, dark when true, row by row.
public struct QRGrid: Equatable, Sendable {
    public let width: Int
    public let modules: [Bool]

    /// The code with a light margin of `quiet` modules on every side (4, as
    /// the standard asks); nil when the modules do not make a square.
    public init?(width: Int, modules: [Bool], quiet: Int = 4) {
        guard width > 0, quiet >= 0, modules.count == width * width else { return nil }
        let outer = width + 2 * quiet
        var out = [Bool](repeating: false, count: outer * outer)
        for row in 0..<width {
            for column in 0..<width where modules[row * width + column] {
                out[(row + quiet) * outer + column + quiet] = true
            }
        }
        self.width = outer
        self.modules = out
    }

    /// Whether the module at `row`, `column` is dark.
    public func dark(_ row: Int, _ column: Int) -> Bool { modules[row * width + column] }
}

/// A person's name by their Matrix id (`@user:server`, as the end-to-end
/// library names them) or their bare id, in what the server said of people;
/// nil when unknown.
public func personName(_ user: String, in people: [String: Person]) -> String? {
    if let p = people[user] { return p.name }
    let bare = user.hasPrefix("@") ? String(user.dropFirst()) : user
    if let p = people[bare] { return p.name }
    if let colon = bare.firstIndex(of: ":"), let p = people[String(bare[..<colon])] { return p.name }
    return nil
}

extension Messages {
    /// A person's name by their Matrix id or their bare id; nil when unknown.
    public func name(of user: String) -> String? { personName(user, in: people) }
}

/// Who a verification is with, as its sheet says it: another person (by
/// name when known, always by id) or the person themself, on which device.
public struct VerificationParty: Equatable, Sendable {
    /// The other person's name, when known (nil for oneself).
    public let name: String?
    /// Their Matrix id.
    public let user: String
    /// The other device, once the library knows it.
    public let device: String?
    /// The person's own other device.
    public let isMe: Bool

    public init(user: String, device: String?, me: String?, people: [String: Person]) {
        self.user = user
        self.device = device.flatMap { $0.isEmpty ? nil : $0 }
        let bare = { (id: String) in id.hasPrefix("@") ? String(id.dropFirst()) : id }
        isMe = me.map { bare($0) == bare(user) } ?? false
        name = isMe ? nil : personName(user, in: people)
    }
}
