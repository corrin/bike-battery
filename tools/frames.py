"""Keyde e-bike controller BLE frames, as built/parsed by com.leveloo 1.9.9.

Line refs are to decompiled/index.js. See docs/protocol.md for the full write-up.
"""
import math

HEADER, TRAILER = 0x55, 0x0D
VER_CMD = b"SI=VER1\r\n"                         # 197294
VOLTAGE_CUTOFF = {24: 19, 30: 22, 33: 26, 36: 29}  # voltage_range[v][0], 197431-197439
MODEL_MAX_POWER = {0: 750, 16: 300, 17: 300, 18: 300, 32: 500, 33: 500, 34: 500,
                   48: 500, 49: 500, 50: 500, 64: 750, 65: 750, 66: 750,
                   80: 400, 81: 400, 96: 500, 97: 500}  # default_setting, 197252
KMH_TO_MPH = 0.6214                               # 197290
PI = 3.14                                         # the app's pi, everywhere


def checksum(body):
    """Low byte of the plain sum of every byte before the checksum (209585-209602, 368113-368140)."""
    return sum(body) & 0xFF


def _js_round(x):
    # ponytail: JS Number.toFixed(0) ~ round-half-up; exact-binary edge cases ignored
    return int(math.floor(x + 0.5))


def max_speed_rpm(max_speed, wheel_mm, mph=False):
    """Wheel rpm at the speed limit (209396-209427). wheel_mm = wheel *diameter* in mm."""
    kmh = max_speed / KMH_TO_MPH if mph else max_speed
    return _js_round(kmh * 1_000_000 / (wheel_mm * PI) / 60)


def build_settings_frame(level, max_speed, wheel_mm, max_power, voltage,
                         mph=False, torque_calibrate=False, torque_mode=False):
    """20-byte frame written every 200 ms to FFF6 / 6E400002 / FFE1 (cacuHexString 209346).

    level: assist level 0..5 (sent as 2*level).  max_speed: km/h (or mph if mph=True).
    max_power: W.  voltage: nominal pack voltage key 24/30/33/36.
    torque_calibrate: global.momentCorrecting ('H-Adjust').  torque_mode: bike_model==1 ('TOR Mode').
    """
    if not 0 <= level <= 5:
        raise ValueError("level must be 0..5")
    rpm = max_speed_rpm(max_speed, wheel_mm, mph) & 0xFFFF
    flags = (torque_calibrate << 6) | (torque_mode << 8)
    f = [0] * 20
    f[0] = HEADER
    f[1] = 2 * level
    f[2], f[3] = rpm >> 8, rpm & 0xFF
    f[4], f[5] = (max_power >> 8) & 0xFF, max_power & 0xFF
    f[6] = VOLTAGE_CUTOFF[voltage] & 0xFF
    f[7], f[8] = flags >> 8, flags & 0xFF
    f[18] = checksum(f[:18])
    f[19] = TRAILER
    return bytes(f)


def build_motor_frame(*args, **kwargs):
    """40-byte variant for BLE-MOTOR devices (cacuHexStringMotor 210243): same first 18 bytes,
    zero padded to 38, checksum at [38], 0x0D at [39]."""
    f = list(build_settings_frame(*args, **kwargs)[:18]) + [0] * 22
    f[38] = checksum(f[:38])
    f[39] = TRAILER
    return bytes(f)


def simac_cmd(mac):
    """Sensor pairing command (386198-386212); all-zero MAC = unpair (370927)."""
    return ("SIMAC=" + mac.replace(":", "") + "\r\n").encode()


def verify(frame):
    """App's frame check (verify, 368088): 0x55 first, 0x0D last, frame[-2] == checksum(frame[:-2])."""
    return (len(frame) >= 3 and frame[0] == HEADER and frame[-1] == TRAILER
            and frame[-2] == checksum(frame[:-2]))


def _js_parse_int(s):
    digits = ""
    for c in s:
        if not c.isdigit():
            break
        digits += c
    return int(digits) if digits else float("nan")


def parse_version(frame):
    """'SI=' reply (211542-211559): bytes 4,5,6 hex-printed then parseInt'd base 10. No checksum."""
    if frame[:3] != b"SI=":
        return None
    return ".".join(str(_js_parse_int("%02X" % b)) for b in frame[4:7])


def parse_status(frame, wheel_mm, motor=False):
    """Decode a status notification (handleUpdateValueForCharacteristic body, 211086-211520).

    Returns None if verify() fails. motor=True also decodes the BLE-MOTOR-only bytes 13/14/24.
    """
    if not verify(frame):
        return None
    be16 = lambda i: (frame[i] << 8) | frame[i + 1]
    flags = frame[9]           # app keeps only the low 8 bits of [8..9] (buling(...,8))
    err = frame[11]            # same truncation for [10..11]
    rpm = be16(4)
    circ_m = wheel_mm * PI * 0.001
    speed = min(round(rpm * circ_m * 60 * 0.001, 1), 80) if rpm else 0.0
    total_roll = be16(16) * 500
    out = {
        "power_w": be16(1),
        "voltage_v": frame[3],
        "rpm": rpm,
        "cadence_rpm": be16(6),            # foot_rpm
        "flags": flags,
        "torque_calibrated": (flags >> 3) & 1,   # momentCorrect
        "motor_flag": (flags >> 4) & 1,          # global.motor (750 W picker range)
        "second_battery": (flags >> 5) & 1,      # state.ex -> show voltage_ex
        "error_bits": format(err, "08b"),        # temp_error, MSB first
        "temperature_c": frame[12],
        "voltage_ex_v": frame[15],
        "total_roll": total_roll,
        "speed_kmh": speed,
        "odometer_km": total_roll * circ_m * 0.001,
    }
    if motor:
        out["level"] = frame[13] / 2
        out["model_code"] = frame[14]
        out["model_max_power_w"] = MODEL_MAX_POWER.get(frame[14])
        out["motor_helper_bits"] = [(frame[24] >> i) & 1 for i in range(8)]
    return out


if __name__ == "__main__":
    # Defaults from 197275/197282/197305: 29" wheel (736.6 mm), 30 V, 36 km/h, 750 W.
    assert max_speed_rpm(36, 736.6) == 259          # 36e6/(736.6*3.14)/60 = 259.4
    assert max_speed_rpm(25, 736.6) == 180          # 180.15
    assert max_speed_rpm(15.535, 736.6, mph=True) == 180  # 15.535 mph ~ 25 km/h

    f = build_settings_frame(level=2, max_speed=25, wheel_mm=736.6, max_power=500,
                             voltage=36, torque_mode=True)
    # hand-computed: 55+04+B4+01+F4+1D+01 = 0x220 -> 0x20
    assert f.hex(" ").upper() == "55 04 00 B4 01 F4 1D 01 00 00 00 00 00 00 00 00 00 00 20 0D", f.hex(" ")
    assert verify(f)

    g = build_settings_frame(0, 36, 736.6, 750, 30, torque_calibrate=True)
    assert g[:9] == bytes([0x55, 0, 0x01, 0x03, 0x02, 0xEE, 0x16, 0x00, 0x40])
    assert g[18] == (0x55 + 0x01 + 0x03 + 0x02 + 0xEE + 0x16 + 0x40) & 0xFF == 0x9F

    m = build_motor_frame(2, 25, 736.6, 500, 36, torque_mode=True)
    assert len(m) == 40 and m[:18] == f[:18] and m[38] == 0x20 and m[39] == 0x0D and verify(m)

    assert simac_cmd("AA:BB:CC:DD:EE:FF") == b"SIMAC=AABBCCDDEEFF\r\n"
    assert len(VER_CMD) == 9                        # why cacuHexStringMotor tests length 9

    # Sample status frame (constructed, not captured): 300 W, 36 V, 180 rpm, cadence 60,
    # flags 0x38, 30 C, gear byte 4, model 0x40, odo counter 100.
    body = bytes.fromhex("55 012C 24 00B4 003C 0038 0000 1E 04 40 00 0064")
    s = body + bytes([checksum(body), 0x0D])
    assert len(s) == 20 and s[18] == (sum(body) & 0xFF)
    d = parse_status(s, 736.6)
    assert d["power_w"] == 300 and d["voltage_v"] == 36 and d["rpm"] == 180
    assert d["cadence_rpm"] == 60 and d["temperature_c"] == 30
    assert (d["torque_calibrated"], d["motor_flag"], d["second_battery"]) == (1, 1, 1)
    assert d["speed_kmh"] == 25.0                   # 180*2.312924*60/1000 = 24.98
    assert d["total_roll"] == 50000 and abs(d["odometer_km"] - 115.6462) < 1e-3
    bad = bytearray(s); bad[18] ^= 1
    assert parse_status(bytes(bad), 736.6) is None

    mf = bytearray(40); mf[:18] = s[:18]; mf[24] = 0b101; mf[39] = 0x0D
    mf[38] = checksum(mf[:38])
    dm = parse_status(bytes(mf), 736.6, motor=True)
    assert dm["level"] == 2 and dm["model_max_power_w"] == 750 and dm["motor_helper_bits"][:3] == [1, 0, 1]

    # error word: only low byte survives buling(bin, 8)
    e = bytearray(s); e[10], e[11] = 0x01, 0x82; e[18] = checksum(e[:18])
    assert parse_status(bytes(e), 736.6)["error_bits"] == "10000010"

    assert parse_version(b"SI=V\x01\x00\x03\r\n") == "1.0.3"
    print("all self-checks passed")
