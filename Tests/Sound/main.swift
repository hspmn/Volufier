import Foundation
var sound = SoundSettings()
let original: [UInt8] = [2,2,0,30,3,2,1]
precondition(sound.command(for: .room(.mode,1)) == nil)
precondition(sound.read(.room, original))
for field in SoundField.allCases {
    for value in field.values {
        let cmd = sound.command(for: .room(field, value))!
        var expected = original; expected[field.rawValue] = UInt8(value)
        precondition(cmd.0 == 0xc4 && cmd.1 == expected && cmd.2 == .room)
    }
}
precondition(sound.command(for: .room(.cutoff, 43)) == nil)
precondition(!sound.read(.room, [2,2,1,30,3,2,1]))
var curve: [UInt8] = [12,9,0]
for (i,hz) in [62,125,250,500,1000,2000,4000,8000,16000].enumerated() {
    curve += [UInt8(i),UInt8(hz >> 8),UInt8(hz & 255),6]
}
precondition(sound.read(.eq, curve))
precondition(sound.command(for:.gain(8,10))!.1 == [0,8,62,128,10])
precondition(sound.command(for:.gain(0,13)) == nil)
precondition(!sound.read(.eq, Array(curve.dropLast())))
precondition(sound.command(for:.gain(0,3)) == nil)
precondition(sound.read(.power,[1]) && sound.confirms(.power(true)))
precondition(sound.command(for:.power(false))!.1 == [0])
print("Validated tuning preservation, all field ranges, EQ encoding and power saving.")
