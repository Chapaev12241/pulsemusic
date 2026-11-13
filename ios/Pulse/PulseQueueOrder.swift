import Foundation

enum PulseQueueOrder {
    static func shuffled<T>(_ tracks: [T], keeping current: String, key: (T) -> String) -> [T] {
        guard let selected = tracks.first(where: { key($0) == current }) else { return tracks.shuffled() }
        return [selected] + tracks.filter { key($0) != current }.shuffled()
    }
}
