import XCTest
#if os(iOS)
@testable import Pulse
#else
@testable import PulseMac
#endif

final class PulseDevicesTests: XCTestCase {
    func testDeviceProtocolPreservesPositionAndBothQueueOrders() throws {
        let state = PulseDeviceState(trackId: String(repeating: "a", count: 64), position: 87.25, duration: 242, paused: false, buffering: false, shuffle: true, dj: true, volume: 0.6)
        let encoded = try JSONSerialization.data(withJSONObject: state.json)
        XCTAssertEqual(try JSONDecoder().decode(PulseDeviceState.self, from: encoded), state)
        let one = String(repeating: "a", count: 64), two = String(repeating: "b", count: 64)
        let data = try JSONSerialization.data(withJSONObject: ["deviceId": "phone", "devices": [], "focus": ["deviceId": "mac", "revision": 3, "name": "Mac", "online": true, "state": state.json], "command": ["id": "command", "type": "transfer", "createdAt": 1700000000000.0, "payload": ["state": state.json, "queue": [two, one], "originalQueue": [one, two], "sourceId": "phone"]], "serverTime": 1700000000100.0])
        let response = try JSONDecoder().decode(PulseDevicesResponse.self, from: data)
        XCTAssertEqual(response.command?.payload.state?.position, 87.25)
        XCTAssertEqual(response.command?.payload.queue, [two, one])
        XCTAssertEqual(response.command?.payload.originalQueue, [one, two])
        XCTAssertEqual(response.focus.deviceId, "mac")
        XCTAssertEqual(response.focus.state?.shuffle, true)
    }
}
