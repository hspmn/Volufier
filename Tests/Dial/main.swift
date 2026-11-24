import Foundation
for level in 0...30 {
    let radians = DialGeometry.position(level: level) * .pi / 180
    let measured = DialGeometry.angle(x: 95*sin(radians), y: -95*cos(radians))
    precondition(DialGeometry.level(at: measured) == level)
}
precondition(DialGeometry.level(at: 180) == nil)
precondition(DialGeometry.level(at: -179) == nil)
precondition(DialGeometry.change(from: 178, to: -179) == 3)
precondition(DialGeometry.change(from: -178, to: 179) == -3)
print("All 31 stops, bottom dead zone and clockwise/counterclockwise transitions passed.")
