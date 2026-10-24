// Run in CI: swiftc ios/Bike/Frame.swift ios/selftest/main.swift
// Test vectors are constructed from docs/protocol.md; add real captured frames here once we have them.

func frame(_ body: [UInt8], length: Int) -> [UInt8] {
    var f = body + [UInt8](repeating: 0, count: length - 2 - body.count)
    f.append(UInt8(f.reduce(0) { $0 + Int($1) } & 0xFF))
    f.append(0x0D)
    return f
}

// 300 W, 36 V, 180 rpm, cadence 60, flags 0x18 (no second battery), 30 C, level byte 4, model 0x40, 2nd batt 40 V, odo 100
let body: [UInt8] = [0x55, 0x01, 0x2C, 0x24, 0x00, 0xB4, 0x00, 0x3C, 0x00, 0x18, 0x00, 0x00, 0x1E, 0x04, 0x40, 0x28, 0x00, 0x64]
let f20 = frame(body, length: 20)
let f40 = frame(body, length: 40)

assert(isValidFrame(f20[...]) && isValidFrame(f40[...]))
var bad = f20; bad[18] ^= 1
assert(!isValidFrame(bad[...]))
assert(parseStatus(f40) == Status(powerW: 300, volts: 36))

var ex = body; ex[9] = 0x38   // second-battery flag set -> volts from byte 15
assert(parseStatus(frame(ex, length: 40)) == Status(powerW: 300, volts: 40))

// A 40-byte frame split across two notifications, with junk in front.
var buf: [UInt8] = [0x00, 0x13] + Array(f40[0..<20])
assert(takeFrames(&buf).isEmpty && buf.count == 20)
buf += f40[20...]
assert(takeFrames(&buf) == [f40] && buf.isEmpty)

// Back-to-back 20-byte frames.
buf = f20 + f20
assert(takeFrames(&buf) == [f20, f20] && buf.isEmpty)

let s = Settings(fullV: 42, emptyV: 32, kmPerCharge: 40)
assert(batteryPercent(volts: 37, s) == 50 && rangeKm(volts: 37, s) == 20)
assert(batteryPercent(volts: 30, s) == 0 && batteryPercent(volts: 45, s) == 100)
assert(batteryPercent(volts: 37, Settings(fullV: 32, emptyV: 32, kmPerCharge: 40)) == 0)
assert(summary(volts: 37, s) == "Bike battery 50 percent, about 20 kilometres.")

print("all self-checks passed")
