import Foundation

enum Frames {
    static let model: UInt8 = 0xc9
    static let volume: UInt8 = 0x66
    static let setVolume: UInt8 = 0x67

    static func request(_ command: UInt8, code: UInt8, payload: [UInt8] = []) -> Data {
        var bytes: [UInt8] = [0xaa, code, command, 0, UInt8(payload.count)]
        bytes += payload
        bytes.append(bytes.reduce(0, &+))
        return Data(bytes)
    }

    struct Reply {
        let command: UInt8
        let payload: [UInt8]
    }

    struct Decoder {
        private var bytes: [UInt8] = []

        mutating func append(_ data: Data) -> [Reply] {
            bytes.append(contentsOf: data)
            var result: [Reply] = []
            while !bytes.isEmpty {
                guard bytes[0] == 0xbb else { bytes.removeFirst(); continue }
                guard bytes.count >= 5 else { break }
                let length = Int(bytes[3]) * 256 + Int(bytes[4])
                guard length <= 512 else { bytes.removeFirst(); continue }
                let end = 5 + length
                guard bytes.count > end else { break }
                guard bytes[..<end].reduce(0, &+) == bytes[end] else { bytes.removeFirst(); continue }
                result.append(Reply(command: bytes[2], payload: Array(bytes[5..<end])))
                bytes.removeFirst(end + 1)
            }
            return result
        }
    }

    static func isMR5(_ data: [UInt8]) -> Bool {
        let model = String(bytes: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)).uppercased()
        return model == "EDIFIER MR5" || model == "MR5"
    }

    static func level(_ payload: [UInt8]) -> Int? {
        guard payload.count == 2, payload[0] == 30, payload[1] <= 30 else { return nil }
        return Int(payload[1])
    }
}
