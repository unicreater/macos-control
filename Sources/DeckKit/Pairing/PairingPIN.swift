import Foundation

/// The six-digit code the Mac shows in its menu bar and the phone types in (FR-2).
///
/// A validated value type rather than a `String` so "is this even a PIN?" is answered
/// once, at the edge, instead of at every call site.
public struct PairingPIN: Hashable, Sendable, CustomStringConvertible {
    public static let length = 4

    public let digits: String

    /// Fails for anything that is not exactly six ASCII digits. Surrounding whitespace
    /// is tolerated — pasting from a message shouldn't be a hard error.
    public init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == PairingPIN.length else { return nil }
        guard trimmed.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        self.digits = trimmed
    }

    private init(unchecked digits: String) {
        self.digits = digits
    }

    public static func random<G: RandomNumberGenerator>(using generator: inout G) -> PairingPIN {
        var digits = ""
        for _ in 0..<PairingPIN.length {
            digits.append(String(Int.random(in: 0...9, using: &generator)))
        }
        return PairingPIN(unchecked: digits)
    }

    public static func random() -> PairingPIN {
        var generator = SystemRandomNumberGenerator()
        return random(using: &generator)
    }

    /// The individual digits, for the six 56×74pt cells of the PIN screen (design S3).
    public var characters: [Character] { Array(digits) }

    public var description: String { digits }
}
