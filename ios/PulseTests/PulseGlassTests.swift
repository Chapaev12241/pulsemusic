import XCTest
#if os(iOS)
@testable import Pulse
#else
@testable import PulseMac
#endif

final class PulseGlassTests: XCTestCase {
    @MainActor private final class MotionSource: PulseMotionSource {
        var available = true
        var starts = 0, stops = 0
        var receive: ((CGPoint?) -> Void)?
        func start(_ receive: @escaping (CGPoint?) -> Void) { starts += 1; self.receive = receive }
        func stop() { stops += 1 }
    }
    func testTiltRejectsInvalidReadingsAndBoundsExtremeRotation() {
        XCTAssertEqual(PulseGlassTilt.normalized(CGPoint(x: 20, y: -20), relativeTo: .zero), CGPoint(x: 1, y: -1))
        XCTAssertEqual(PulseGlassTilt.normalized(CGPoint(x: CGFloat.nan, y: 1), relativeTo: .zero), .zero)
        XCTAssertEqual(PulseGlassTilt.normalized(CGPoint(x: 0.2, y: 0.4), relativeTo: CGPoint(x: 0.2, y: 0.4)), .zero)
    }
    @MainActor
    func testMotionStopsResetsAndRejectsStaleSamplesInBackground() async {
        let source = MotionSource()
        let controller = PulseGlassMotion(source: source)
        controller.setEnabled(true); controller.setEnabled(true)
        XCTAssertEqual(source.starts, 1)
        source.receive?(.zero); source.receive?(CGPoint(x: 0.3, y: 0.2))
        XCTAssertGreaterThan(controller.tilt.x, 0)
        let oldCallback = source.receive
        controller.setEnabled(false)
        XCTAssertEqual(source.stops, 1)
        XCTAssertFalse(controller.active)
        XCTAssertEqual(controller.tilt, .zero)
        oldCallback?(CGPoint(x: -0.5, y: 0.5))
        XCTAssertEqual(controller.tilt, .zero)
        controller.setEnabled(true); source.receive?(CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(controller.tilt, .zero, "Resuming recalibrates to the current phone position")
        controller.setEnabled(false)
    }
    @MainActor
    func testUnavailableSensorAndSensorErrorLeaveStaticGlass() async {
        let source = MotionSource(); source.available = false
        let controller = PulseGlassMotion(source: source)
        controller.setEnabled(true)
        XCTAssertFalse(controller.active); XCTAssertEqual(source.starts, 0)
        source.available = true; controller.setEnabled(true); source.receive?(nil)
        XCTAssertFalse(controller.active); XCTAssertEqual(controller.tilt, .zero)
        XCTAssertEqual(source.stops, 1)
    }
}
