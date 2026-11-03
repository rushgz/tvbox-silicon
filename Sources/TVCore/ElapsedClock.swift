import Foundation
import SwiftUI

/// A binding to a property of a perceptible object. iOS 16 has no `@Bindable`, and the Perception
/// backport of it is unavailable once the deployment target reaches the OS that ships the real one.
public func binding<Root, Value>(_ root: Root, _ keyPath: ReferenceWritableKeyPath<Root, Value>) -> Binding<Value> {
    Binding(get: { root[keyPath: keyPath] }, set: { root[keyPath: keyPath] = $0 })
}

/// A point on a monotonic clock, standing in for `ContinuousClock.Instant`, which needs iOS 16.
/// Subtracting two points gives the elapsed time as a `Duration16`.
public struct ElapsedInstant: Comparable, Sendable {
    fileprivate let uptime: TimeInterval
    public static func now() -> ElapsedInstant { ElapsedInstant(uptime: ProcessInfo.processInfo.systemUptime) }
    public static func < (lhs: ElapsedInstant, rhs: ElapsedInstant) -> Bool { lhs.uptime < rhs.uptime }
    public func duration(to later: ElapsedInstant) -> Duration16 { Duration16(seconds: later.uptime - uptime) }
    public func advanced(by duration: Duration16) -> ElapsedInstant { ElapsedInstant(uptime: uptime + duration.seconds) }
}

public struct Duration16: Comparable, Sendable, CustomStringConvertible {
    public let seconds: TimeInterval
    public static func seconds(_ value: Double) -> Duration16 { Duration16(seconds: value) }
    public static func < (lhs: Duration16, rhs: Duration16) -> Bool { lhs.seconds < rhs.seconds }
    public var description: String { String(format: "%.3fs", seconds) }
}
