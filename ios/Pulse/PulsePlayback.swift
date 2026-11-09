import SwiftUI

// Only the transport observes this clock. A 4 Hz playback tick must not publish
// the entire library or invalidate hundreds of track rows.
@MainActor
final class PulsePlayback: ObservableObject {
    @Published var time = 0.0
    @Published var duration = 0.0
    @Published var paused = true
    @Published var buffering = false
    @Published var currentID = ""
    @Published var equalizerActive = false
    private(set) var updatedAt = Date()
    var interpolatedTime: Double { time + (paused || buffering ? 0 : min(0.35, max(0, Date().timeIntervalSince(updatedAt)))) }
    func receive(_ value: [String: Any]) {
        if let next = value["equalizerActive"] as? Bool, next != equalizerActive { equalizerActive = next }
        if let next = value["time"] as? Double { updatedAt = Date(); if next != time { time = next } }
        if let next = value["duration"] as? Double, next != duration { duration = next }
        if let next = value["paused"] as? Bool, next != paused { paused = next }
        if let next = value["buffering"] as? Bool, next != buffering { buffering = next }
        if let next = value["id"] as? String, next != currentID { currentID = next }
    }
}
