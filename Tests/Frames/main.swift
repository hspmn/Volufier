import Foundation
var decoder = Frames.Decoder()
let query = Data([0xaa,0xec,0x66,0x00,0x00,0xfc])
let status = Data([0xbb,0xec,0x66,0x00,0x02,0x1e,0x08,0x35])
let ack = Data([0xbb,0xec,0x67,0x00,0x01,0x01,0x10])
precondition(Frames.request(Frames.volume, code: 0xec) == query)
precondition(Frames.request(Frames.model, code: 0xec) == Data([0xaa,0xec,0xc9,0,0,0x5f]))
for (level, check) in [(8,6),(9,7),(10,8)] {
    precondition(Frames.request(Frames.setVolume, code: 0xec, payload: [UInt8(level)]) == Data([0xaa,0xec,0x67,0,1,UInt8(level),UInt8(check)]))
}
precondition(decoder.append(status.prefix(4)).isEmpty)
let replies = decoder.append(status.dropFirst(4) + ack)
precondition(replies.count == 2 && Frames.level(replies[0].payload) == 8 && replies[1].command == Frames.setVolume)
precondition(decoder.append(status.dropLast() + Data([0x00])).isEmpty)
precondition(decoder.append(status).count == 1)
precondition(Frames.isMR5(Array("EDIFIER MR5".utf8)))
precondition(!Frames.isMR5(Array("EDIFIER MR3".utf8)))
precondition(Frames.level([30,31]) == nil && Frames.level([30,0]) == 0 && Frames.level([30,30]) == 30)
print("MR5 capture, checksum, model identity, scale limits, fragmentation and acknowledgement checks passed")
