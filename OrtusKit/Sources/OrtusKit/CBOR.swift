// The little CBOR (RFC 8949) WebAuthn needs: unsigned and negative
// integers, byte and text strings, maps with integer or text keys.
import Foundation

public indirect enum CBOR: Equatable {
    case unsigned(UInt64)
    case negative(Int64)
    case bytes(Data)
    case text(String)
    case map([(CBOR, CBOR)])

    public static func == (a: CBOR, b: CBOR) -> Bool { a.encoded == b.encoded }

    private static func head(_ major: UInt8, _ value: UInt64) -> Data {
        let m = major << 5
        switch value {
        case 0..<24: return Data([m | UInt8(value)])
        case 24..<256: return Data([m | 24, UInt8(value)])
        case 256..<65536: return Data([m | 25, UInt8(value >> 8), UInt8(value & 0xff)])
        case 65536..<4_294_967_296:
            return Data([m | 26] + (0..<4).reversed().map { UInt8((value >> (UInt64($0) * 8)) & 0xff) })
        default:
            return Data([m | 27] + (0..<8).reversed().map { UInt8((value >> (UInt64($0) * 8)) & 0xff) })
        }
    }

    public var encoded: Data {
        switch self {
        case .unsigned(let v): return CBOR.head(0, v)
        case .negative(let v): return CBOR.head(1, UInt64(-1 - v))
        case .bytes(let d): return CBOR.head(2, UInt64(d.count)) + d
        case .text(let s):
            let d = Data(s.utf8)
            return CBOR.head(3, UInt64(d.count)) + d
        case .map(let pairs):
            var out = CBOR.head(5, UInt64(pairs.count))
            for (k, v) in pairs { out += k.encoded + v.encoded }
            return out
        }
    }
}
