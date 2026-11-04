import Foundation
import Perception
import Testing
@testable import TVCore

@Perceptible private final class BindingModel {
    struct Preferences { var volume = 0.5 }
    var enabled = false
    var preferences = Preferences()
}

private final class BindingChanges: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func record() { lock.withLock { count += 1 } }
}

struct BindingObservationTests {
    @Test func bindingTracksExternalChangesBeforeAControlReadsItsValue() {
        let model = BindingModel(), changes = BindingChanges()
        let control = withPerceptionTracking { binding(model, \.enabled) } onChange: { changes.record() }
        model.enabled = true
        #expect(changes.value == 1)
        #expect(control.wrappedValue)
    }

    @Test func nestedBindingTracksReplacementAndWritesBackToTheModel() {
        let model = BindingModel(), changes = BindingChanges()
        let control = withPerceptionTracking { binding(model, \.preferences.volume) } onChange: { changes.record() }
        model.preferences = .init(volume: 0.8)
        #expect(changes.value == 1)
        #expect(control.wrappedValue == 0.8)
        control.wrappedValue = 0.2
        #expect(model.preferences.volume == 0.2)
    }

    @Test func unrelatedPropertiesDoNotInvalidateABinding() {
        let model = BindingModel(), changes = BindingChanges()
        _ = withPerceptionTracking { binding(model, \.enabled) } onChange: { changes.record() }
        model.preferences.volume = 0.9
        #expect(changes.value == 0)
        model.enabled = true
        #expect(changes.value == 1)
    }
}
