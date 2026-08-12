import Foundation

/// How long to wait before the next reconnect attempt.
///
/// Exponential with jitter, but capped at five seconds — FR-4 requires the deck back
/// within five seconds of the Mac being reachable again, so no backoff step may exceed
/// that no matter how long the outage lasted.
public struct ReconnectPolicy: Hashable, Sendable {
    public var initialDelay: TimeInterval
    public var multiplier: Double
    public var maximumDelay: TimeInterval
    /// Fraction of the delay to spread randomly either side of it, so two phones that
    /// dropped together don't retry in lockstep forever.
    public var jitterFraction: Double

    public init(
        initialDelay: TimeInterval = 0.5,
        multiplier: Double = 2,
        maximumDelay: TimeInterval = 5,
        jitterFraction: Double = 0.2
    ) {
        self.initialDelay = initialDelay
        self.multiplier = multiplier
        self.maximumDelay = maximumDelay
        self.jitterFraction = jitterFraction
    }

    public static let `default` = ReconnectPolicy()

    /// Delay before attempt number `attempt`, counting from zero.
    ///
    /// `randomUnit` is the jitter draw, taken as a parameter rather than rolled inside
    /// so the curve is testable. Callers pass `Double.random(in: 0...1)`.
    public func delay(forAttempt attempt: Int, randomUnit: Double) -> TimeInterval {
        let step = max(attempt, 0)
        let growth = pow(multiplier, Double(step))
        // `growth` overflows to .infinity for absurd attempt counts; min() handles that
        // correctly, but a NaN would not, so it is filtered first.
        let uncapped = growth.isNaN ? maximumDelay : initialDelay * growth
        let base = min(uncapped, maximumDelay)

        let unit = min(max(randomUnit, 0), 1)
        let spread = base * jitterFraction
        let jittered = base - spread + (2 * spread * unit)
        return min(max(jittered, 0), maximumDelay)
    }

    public func delay(forAttempt attempt: Int) -> TimeInterval {
        delay(forAttempt: attempt, randomUnit: Double.random(in: 0...1))
    }
}
