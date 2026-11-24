import Foundation

enum DialGeometry {
    static let step = 9.0
    static let limit = 30

    // Zero radians is twelve o'clock. Clockwise angles are positive.
    static func angle(x: Double, y: Double) -> Double { atan2(x, -y) * 180 / .pi }
    static func position(level: Int) -> Double { -135 + Double(level) * step }

    static func level(at angle: Double) -> Int? {
        guard abs(angle) <= 139.5 else { return nil } // lower gap between stops
        return Int(min(30, max(0, ((angle + 135) / step).rounded())))
    }

    static func change(from previous: Double, to current: Double) -> Double {
        let diff = current - previous
        if diff > 180 { return diff - 360 }
        if diff < -180 { return diff + 360 }
        return diff
    }
}
