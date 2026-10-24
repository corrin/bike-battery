import Foundation

// Keyde controller status frames, battery fields only. Port of tools/frames.py; see docs/protocol.md §3.

struct Status: Equatable {
    let powerW: Int
    let volts: Int
}

struct Settings {
    var fullV: Double
    var emptyV: Double
    var kmPerCharge: Double
}

let header: UInt8 = 0x55
let trailer: UInt8 = 0x0D

/// 0x55 first, 0x0D last, second-to-last = low byte of the sum of everything before it (app's verify()).
func isValidFrame(_ b: ArraySlice<UInt8>) -> Bool {
    guard b.count >= 20, b.first == header, b.last == trailer else { return false }
    let sum = b.dropLast(2).reduce(0) { $0 + Int($1) }
    return b[b.endIndex - 2] == UInt8(sum & 0xFF)
}

/// Removes complete frames (40-byte BLE-MOTOR or 20-byte) from the front of `buf`, dropping junk.
/// Notifications can split a frame, so an incomplete tail is kept for the next call.
func takeFrames(_ buf: inout [UInt8]) -> [[UInt8]] {
    var out: [[UInt8]] = []
    var i = 0
    while i < buf.count {
        guard buf[i] == header else { i += 1; continue }
        if let n = [40, 20].first(where: { i + $0 <= buf.count && isValidFrame(buf[i..<i + $0]) }) {
            out.append(Array(buf[i..<i + n]))
            i += n
        } else if buf.count - i < 40 {
            break
        } else {
            i += 1
        }
    }
    buf.removeFirst(i)
    return out
}

/// Bytes 1-2 power (W), byte 3 pack voltage; flag bit 5 of byte 9 means use the second battery (byte 15).
func parseStatus(_ f: [UInt8]) -> Status {
    let secondBattery = (f[9] >> 5) & 1 == 1
    return Status(powerW: Int(f[1]) << 8 | Int(f[2]), volts: Int(secondBattery ? f[15] : f[3]))
}

// ponytail: linear voltage->% is crude (Li-ion curve isn't linear); fine at whole-volt resolution.
func batteryPercent(volts: Int, _ s: Settings) -> Int {
    guard s.fullV > s.emptyV else { return 0 }
    let f = (Double(volts) - s.emptyV) / (s.fullV - s.emptyV)
    return Int((min(max(f, 0), 1) * 100).rounded())
}

func rangeKm(volts: Int, _ s: Settings) -> Int {
    Int((Double(batteryPercent(volts: volts, s)) / 100 * s.kmPerCharge).rounded())
}

func summary(volts: Int, _ s: Settings) -> String {
    "Bike battery \(batteryPercent(volts: volts, s)) percent, about \(rangeKm(volts: volts, s)) kilometres."
}
