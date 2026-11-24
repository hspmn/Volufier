import Foundation

enum SoundField: Int, CaseIterable {
    case mode = 0, cutoff = 3, slope = 4, space = 5, desktop = 6
    var values: [Int] {
        switch self {
        case .mode: return [0, 1, 2]
        case .cutoff: return Array(stride(from: 20, through: 100, by: 5))
        case .slope: return Array(0...3)
        case .space: return Array(0...4)
        case .desktop: return [0, 1]
        }
    }
}

struct SoundSettings {
    enum Group: UInt8, CaseIterable { case room = 0xd5, eq = 0x43, power = 0xb1 }
    enum Edit {
        case room(SoundField, Int)
        case gain(Int, Int)
        case power(Bool)
    }
    struct Band: Identifiable {
        let id: UInt8
        let hz: Int
        let gain: Int
    }
    var room: [UInt8]?
    var bands: [Band] = []
    private var slot: UInt8?
    var power: Bool?

    mutating func read(_ group: Group, _ p: [UInt8]) -> Bool {
        switch group {
        case .room:
            guard p.count == 7, p[2] == 0,
                  SoundField.allCases.allSatisfy({ $0.values.contains(Int(p[$0.rawValue])) }) else {
                room = nil; return false
            }
            room = p
        case .power:
            guard p.count == 1, p[0] <= 1 else { power = nil; return false }
            power = p[0] == 1
        case .eq:
            bands = []; slot = nil
            guard p.count >= 39, p[0] == 12, p[1] == 9 else { return false }
            var decoded: [Band] = []
            for i in 0..<9 {
                let offset = 3 + i * 4
                let hz = Int(p[offset + 1]) * 256 + Int(p[offset + 2])
                guard p[offset] == UInt8(i), hz > (decoded.last?.hz ?? 0), hz <= 24000,
                      p[offset + 3] <= 12 else { return false }
                decoded.append(Band(id: p[offset], hz: hz, gain: Int(p[offset + 3])))
            }
            slot = p[2]; bands = decoded
        }
        return true
    }

    func command(for edit: Edit) -> (UInt8, [UInt8], Group)? {
        switch edit {
        case let .room(field, value):
            guard var bytes = room, field.values.contains(value) else { return nil }
            bytes[field.rawValue] = UInt8(value)
            return (0xc4, bytes, .room)
        case let .gain(index, gain):
            guard let slot, bands.indices.contains(index), (0...12).contains(gain) else { return nil }
            let band = bands[index]
            return (0x44, [slot, band.id, UInt8(band.hz >> 8), UInt8(band.hz & 255), UInt8(gain)], .eq)
        case let .power(on):
            guard power != nil else { return nil }
            return (0xb2, [on ? 1 : 0], .power)
        }
    }
    func confirms(_ edit: Edit) -> Bool {
        switch edit {
        case let .room(field, value): return room.map { Int($0[field.rawValue]) == value } ?? false
        case let .gain(index, gain): return bands.indices.contains(index) && bands[index].gain == gain
        case let .power(on): return power == on
        }
    }
}
