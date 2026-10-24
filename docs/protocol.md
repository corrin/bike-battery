# Keyde controller BLE protocol (com.leveloo 1.9.9)

Source: Hermes decompile `decompiled/index.js`. `Lnnnn` = line number in that file.
**V** = read directly from code. **(inferred)** = my interpretation, not literally in code.
Runnable encoder/decoder with self-checks: `tools/frames.py`.

## BLE-MOTOR summary (variant 3, the user's bike)

- **Transport.** Nordic UART: the app writes to 6E400002 and receives notifications on 6E400003 (L374995). The device object's `notify:0` / `write:1` flags are **never read**: grep finds no `.notify` / `.write` property reads on device objects. So the app does **not** skip notifications. `openNotify` always calls `startNotification(uuid, serviceId, notifyChar)` (L206696). On Android it first calls `requestMTU(uuid, 247)` (L210154). The app makes no GATT reads at all; the only `.read` is the wrapper definition at L203551. **V.**
- **Telemetry.** There is no request/response poll. The controller must push status notifications by itself. The parser is shared with the other variants (§3.2), plus extra bytes 13/14/24 that only BLE-MOTOR uses. **V.**
- **Writes are driven by notifications.** After the first 40-byte settings frame, which is sent when notify starts (L206692-206770), further frames are sent only **from inside the notification handler**. A frame goes out when a setting changed (`state.handler==1`), when `motor_handler` is set, or when calibration is running. It is throttled to at most once per 1000 ms and skipped if identical to the last frame sent (L211520-211560, L210477). **If the bike never notifies, the app never sends a second frame.** **V.**
- **Battery data: yes, voltage only.**
  - Byte 3 of every status frame is the battery voltage in whole volts, and byte 15 is the second-battery voltage. Neither is gated on `ble_motor` (L211124, L211148). **V.**
  - **Percent is computed by the app, not sent by the device.** `set_dianchi(voltage)` runs every 1 s from `_timer_cacu` (L210959). That timer runs for BLE-MOTOR too: `write_timely` skips only the 200 ms write timer when ble_motor≠0, and still starts `_timer_cacu` (L210575-210580 → case 120). **V.**
    - `set_dianchi` latches the lowest voltage seen while power < 100 W.
    - It maps voltage to percent **only when the pack setting is 30 V**: ≥31→100, ≥29.5→80, ≥28→60, ≥26.5→40, ≥25→20, else 0. Every other pack setting gives 0 % (L208729-208838). **V.**
    - If status flag bit 5 (`ex`, second battery) is set, `set_dianchi_ex(voltage_ex)` (L210969, L208839) also writes `dianchi_percent` from **byte 15**, using step tables for each pack setting (read from the code; boundary handling approximate):
      - 24 V: ≥28.5→100, ≥26→75, ≥23.5→50, ≥21→25, else 10
      - 30 V: ≥31→100, ≥29.5→80, ≥28→60, ≥26.5→40, ≥25→20
      - 33 V: ≥36.5→100, ≥34→75, ≥31→50, ≥28→25, else 10
      - 36 V: ≥41→100, ≥37→75, ≥34→50, ≥31→25, else 10
      
      It also sets a 0–5 bar count using `zeng_range=[25,38]` in 2.6 V steps (L209055-209100).
  - **No range / remaining-km figure exists.**
    - No field for it in the frame.
    - No UI string for it: the English dictionary at L235078 has only "Battery power", "Voltage", "POWER", "Average power".
    - No formula for it: the only "range" identifiers are `voltage_range` and `zeng_range`.
    
    The distance figures the app shows are trip ("DISTANCE"), odometer ("ODO"), and average/max speed. All of them are integrated or computed from wheel rpm (§3.2). **V (by exhaustive grep; absence claims rest on grep coverage).**
- **Assist level.** There is **no up/down command**. The level is sent as an absolute value, `2*level` (0–5), in byte 1 of the full settings frame.
  - When the user taps a gear, `set()` (L209108) stores it, sets `handler=1` and recomputes the frame (`write_motor`). The next incoming notification then triggers `really_write_motor`. **V.**
  - The controller reports its current level back in byte 13 (`/2`), and the app adopts it (L211472-211510). So a gear change made on the bike's own buttons shows up in the app. **(inferred from code; meaning of byte 13 as the controller's level is inferred)**
- **No version query** is sent to BLE-MOTOR: `SI=VER1` is gated on `ble_motor==0` (L209362). **V.**

## 0. What the device is

An e-bike **mid/hub-motor controller** with torque-sensor ("TOR Mode", "H-Adjust" = torque-sensor zero calibration) and speed (PAS) modes, 0–5 assist levels, 24/30/33/36 V packs, 250–750 W power limit, 14–45 km/h speed limit. The app is a phone dashboard: it **computes speed, trip and ride time on the phone** from the wheel rpm the controller reports. (V: strings at L235078 `'speed_model': 'SPEED Mode', 'power_model': 'TOR Mode', 'bike_check': 'H-Adjust'`; pickers L371567, L371691, L372264.)

There is **one frame format** for all four variants. The differences are frame length (20 vs 40 bytes), the BLE UUIDs, write type, polling, and a version query.

## 1. Variants and connection sequence

Discovery `handleDiscoverPeripheral` L374948: the name must match `/Keyde/`, or the lower-cased name must match `/motor/` (L16-95 of the function). V.

| # | Name match (L374985-375010) | Service | Write char | Notify char | Flags |
|---|---|---|---|---|---|
| 1 | any other matching name (default) | FFF0 | FFF6 | FFF7 | ble_motor 0, old 0, ver 0 |
| 2 | `Keyde_HA/HB/HC/HD` | 6E400001-B5A3-F393-E0A9-E50E24DCCA9E | 6E400002-… | 6E400003-… | ver 1 |
| 3 | upper-case name `BLE-MOTOR` / `BLE_MOTOR` | same Nordic UART | 6E400002 | 6E400003 | ble_motor 1, forty 1, write 1, notify 0 |
| 4 | `Keyde_D1235` | FFE0 | FFE1 | FFE1 | old 1 |

`forty`, `write` and `notify` are stored but never change behaviour: `forty` is only copied into a global at L207378, and I found no reads of `notify` or `write`. **V** (grep). What changes behaviour is `ble_motor`, `old` and `ver`.

### Sequence (all variants)
1. `connect_timely` L208241 calls `connect()` from `setInterval` every **2000 ms**. While connecting, a guard flag (`_closure1_slot35`) stops overlapping attempts. V.
2. `connect` L210043: it takes devices[0] (uuid, serviceId, characteristicUUID, characteristicUUIDNotify, ble_motor) and calls `BleManager.connect(uuid)` (L210157). V.
3. On **Android with ble_motor==1** (variant 3) it calls `requestMTU(uuid, 247)` before `openNotify` (L210186-210205). Otherwise it goes straight to `openNotify`. V.
4. `openNotify` L206675: it calls `retrieveServices(uuid)`, then after a **200 ms** `setTimeout` calls `startNotification(uuid, serviceId, notifyChar)`. On success it sets `connect=true`, clears the old timers and calls `write_timely()`. If ble_motor is set it also does a single `write_motor()` + `really_write_motor()` (L206692-206770). V.
5. Notifications arrive through `BleManagerDidUpdateValueForCharacteristic` → `handleUpdateValueForCharacteristic` (listener L212150). V.

There is no auth handshake. The only "handshake" is the optional version query (§2.4).

### Polling
- **Variants 1, 2, 4 (ble_motor 0):** `write_timely` L210559 starts `setInterval(write, 200)`, so the settings frame is written **every 200 ms** (L210570-210620). V. This frame is both the poll and the full settings push: every setting change takes effect on the next tick.
- `write` L210350 needs `mm != ''`, `voltage != ''` and `uuid != 0`, and is skipped while `stopWrite` is set (sensor pairing, L212222). V.
  - `old == 1` (variant 4) → `writeWithoutResponse`. Every other variant → `write` with response, using the RN wrapper's default 20-byte chunking (L203795, L210387-210416). V.
- **Variant 3 (ble_motor 1):** no periodic write. The 40-byte frame is written:
  - once after notify starts;
  - then from inside the notification handler, at most once per **1000 ms**, only if `state.handler==1` (a setting changed), `motor_handler` is true, or calibration is running (L211520-211560).
  - `really_write_motor` L210477 writes only if the frame differs from the last one written (`slot27 != slot37`), with maxByteSize 40.
  V.
- A second 1 s timer (`_timer_cacu`, L210620-210990) computes ride time, average speed, trip and odometer on the phone. V.

## 2. Outgoing frames

### 2.1 Settings / poll frame (20 bytes), `cacuHexString` L209346
| Byte | Value | Source |
|---|---|---|
| 0 | `0x55` header | L209369 |
| 1 | assist level ×2: `[0,2,4,6,8,10][state.index]` (level 0–5) | L209380-209392 |
| 2-3 | speed limit as **wheel rpm**, big-endian u16: `round(max_speed_kmh*1e6/(mm*3.14)/60)`. In mph mode (`state.speed_unit==1`) max_speed is first divided by 0.6214 | L209393-209440 |
| 4-5 | max power in W, big-endian u16 | L209441-209466 |
| 6 | low-voltage cutoff: `voltage_range[voltage][0]` = 24 V→19 (0x13), 30 V→22 (0x16), 33 V→26 (0x1A), 36 V→29 (0x1D) | L209467-209480, table L197431-197439 |
| 7-8 | flags, big-endian u16. bit 6 = `momentCorrecting` (torque-sensor calibration in progress), bit 8 = `bike_model==1` (TOR/torque mode; 0 = speed mode). Built as a 16-element bit array, reversed and parsed base 2, so element *i* is bit *i* | L209481-209520 |
| 9-17 | 0 | L209368 |
| 18 | checksum = `(sum of bytes 0..17) & 0xFF` | L209521-209535 |
| 19 | `0x0D` trailer | L209536-209538 |

- `mm` is the wheel **diameter** in mm. It is `round(inch*25.4)` from the inch list (14 … 31"). A custom value is entered as circumference (1000–2500 mm) and converted by dividing by **3.24** (sic: the code uses 3.24 where it uses 3.14 elsewhere), L377470-377518. The default is 736.6 (29"), L197275. V.
- Every field goes through `buling(hex, n)` = `('0000000000000000'+s).substr(-n)` (L367546). This **truncates** to the low n hex digits: byte 1 to 8 bits, rpm and power to 16 bits. V.
- `momentCorrecting` (bit 6) is set by the Settings "H-Adjust" action `momentCorrect` L370992. Each second it polls `global.momentCorrect` (incoming flag bit 3). It succeeds when that flag becomes 1 and times out after more than 5 s; then it clears `momentCorrecting` (L371000-371060). V.

Ranges from the pickers (V):
- max_speed 14–45 km/h, or 9–28 mph (L371691);
- max_power 250…500 W, or …750 W when the controller reports the `motor` flag, in 50 W steps (L371567);
- voltage 24/30/33/36 (L372264);
- bike_model 0 = SPEED, 1 = TOR (L372376).

Example frames (all computed by `tools/frames.py` and checked by hand):
- level 2, 25 km/h, 29" wheel, 500 W, 36 V, TOR mode:
  `55 04 00 B4 01 F4 1D 01 00 00 00 00 00 00 00 00 00 00 20 0D`
  (checksum: 0x55+0x04+0xB4+0x01+0xF4+0x1D+0x01 = 0x220 → 0x20).
- App defaults (level 0, 36 km/h, 750 W, 30 V) during H-Adjust:
  `55 00 01 03 02 EE 16 00 40 00…00 9F 0D`.

Every "command" goes through this one frame. The full list:

| Setting | Field |
|---|---|
| Assist level / gear (`set`, L209108) | byte 1 |
| Speed limit (also follows speed unit and wheel size) | bytes 2-3 |
| Wheel size | bytes 2-3, indirectly. The wheel size is never sent as its own field |
| Power limit | bytes 4-5 |
| Battery voltage | byte 6 |
| Torque/speed sensor mode | byte 8 bit 0, i.e. flags bit 8 |
| Torque calibration (H-Adjust) | byte 8 bit 6 |

The app has **no light, units or display command**. Units, day/night and right-hand layout are phone-side only.

### 2.2 BLE-MOTOR frame (40 bytes), `cacuHexStringMotor` L210243
Bytes 0–17 are the same as the 20-byte frame. Bytes 18–37 are 0, byte 38 is `sum(bytes 0..37) & 0xFF` (equal to the 20-byte checksum), and byte 39 is `0x0D` (L210255-210300). V.
Example (same settings as above): `55 04 00 B4 01 F4 1D 01 00` + 29×`00` + `20 0D`.

### 2.3 Sensor pairing (ASCII), Settings `scanBle` L370892 / Sensor screen `sendId` L386190
- `SIMAC=<12 hex MAC, colons stripped>\r\n` pairs a BLE sensor (the app scans for names matching `/Sensor/i`, L371400).
- `SIMAC=000000000000\r\n` unpairs (L370927, L371158).
- While pairing, `stopWrite` pauses the 200 ms poll for up to 15 s (L371180). The controller is expected to reply in ASCII containing `succeeded` or `fail`. On `fail` with `reconnect==1` the command is retried once (L211560-211620). V.
- **Unverified / apparent bug:** `writeCgq` (L212479) only stores the command in `_closure1_slot38`. I found **no code that writes slot38 to BLE** (all uses are L206657, L211575-211618, L212481). In this build the SIMAC command may never actually be sent.

### 2.4 Version query (ASCII)
`SI=VER1\r\n` (9 bytes, L197294) replaces the settings frame:
- only for variants with `ver==0 && ble_motor==0` (variants 1 and 4);
- only after the first valid status frame (`communicateOk`);
- at most 5 times (`verInfoTimes < 5`).
(L209353-209366, L209551-209565.) V.

## 3. Incoming notifications

Every byte is turned into 2-digit upper-case hex (L211020-211060). If the frame starts with ASCII `S I =` (`53 49 3D`), it is a **version reply**. Otherwise it is checked with `verify` and parsed as status. V.

### 3.1 Validation, `verify` L368088
These must all hold:
- `b[0] == 0x55`;
- `b[last] == 0x0D`;
- `b[last-1] == (sum of b[0 .. last-2]) & 0xFF`.

On failure the app logs `yz fail` and drops the frame (L211566). The length is not checked. V.

### 3.2 Status frame (20 bytes; variant 3 uses at least 26, **40 inferred** to match the outgoing frame)
| Bytes | Field | Decoding | Line |
|---|---|---|---|
| 1-2 | power | BE u16, **W** | L211118 |
| 3 | battery voltage | u8, **whole volts** | L211124 |
| 4-5 | wheel rpm | BE u16 | L211130 |
| 6-7 | `foot_rpm` (pedal cadence, inferred meaning) | BE u16 | L211136 |
| 8-9 | status flags (`fuzhu`) | **only the low byte (b9) survives** `buling(bin,8)`. bit3 = `momentCorrect` (calibration done), bit4 = `motor` (enables the 750 W picker), bit5 = `ex` (second battery present → show byte 15) | L211087-211116, L211170-211178 |
| 10-11 | error bits | **only b11 survives**. Stored as an 8-char MSB-first string in `state.temp_error`, refreshed at most every 5 s (L211192-211240). Nothing in the UI reads it (grep finds no `.temp_error` reads), so there are no error-code meanings in the app | L211157 |
| 12 | temperature | u8, **°C (inferred unit)**, shown as TEMP | L211142 |
| 13 | (variant 3 only) assist level | `b13/2`. Applied to the UI only when b13 is even, no local change is pending, and a sync latch has been set | L211472-211510 |
| 14 | (variant 3 only) model code | max power = `default_setting[code]` (e.g. 0x10→300 W, 0x20→500 W, 0x40→750 W, 0x50→400 W). It overrides max_power only when the user never stored one | L211415-211460, table L197252 |
| 15 | second-battery voltage | u8, V | L211148 |
| 16-17 | odometer counter | BE u16 × 500 = `total_roll` (wheel revolutions, inferred) | L211162-211168 |
| 24-25 | (variant 3 only) `motor_helper` | parsed as `b25b24`, but only the low 8 bits = **b24** survive. Bit *i* is element *i*, logged as "返回档位" ("returned gear"); not otherwise used | L211462-211490 |
| n-2, n-1 | checksum, `0x0D` | | |

Phone-side derived values (V):
- **speed km/h** = `rpm * mm*3.14/1000 * 60/1000`, rounded to 1 decimal and capped at 80 (L211528-211545, also L210640). It is multiplied by 0.6214 for mph display.
- **odometer km** = `total_roll * mm*3.14/1000/1000`. This is used when `total_roll > 0` (L211168, L210760-210770). Otherwise a phone-integrated odometer is kept in storage.
- **trip km**: speed is integrated every second (L210760-210800).
- **battery %**: see the BLE-MOTOR summary at the top for the full tables. Main battery: only for the 30 V setting. It is taken from the lowest voltage seen while power < 100 W:
  - ≥31 V → 100
  - ≥29.5 → 80
  - ≥28 → 60
  - ≥26.5 → 40
  - ≥25 → 20
  - otherwise 0
  
  Other voltage settings show 0 % (`set_dianchi` L208729). `set_dianchi_ex` L208839 has similar tables for the second battery (24 V: ≥28.5→100, ≥26→75, ≥23.5→50, ≥21→25 …).

### 3.3 Version reply
`53 49 3D xx b4 b5 b6 …`. verInfo = `parseInt(hex(b4)) + '.' + parseInt(hex(b5)) + '.' + parseInt(hex(b6))`. Each byte's **hex text is parsed as decimal**, so raw bytes 0x01 0x00 0x03 give "1.0.3" (L211542-211559). There is no checksum check. Byte 3 is ignored. Bytes 4–6 being raw small integers is (inferred); ASCII digits would give nonsense like "31".

## 4. Worked example

Poll (variant 1): level 2, 25 km/h limit, 29" wheel, 500 W, 36 V, TOR mode.

`55 04 00 B4 01 F4 1D 01 00 00 00 00 00 00 00 00 00 00 20 0D`

- 0x00B4 = 180 rpm, from 25e6/(736.6·3.14)/60 = 180.15.
- 0x01F4 = 500 W.
- 0x1D = 29 V cutoff.
- Flags 0x0100 = TOR mode.

Sample response (constructed, not captured):

`55 01 2C 24 00 B4 00 3C 00 38 00 00 1E 04 40 00 00 64 94 0D`

- checksum: the sum of bytes 0–17 is 0x294 → 94 ✓
- power 0x012C = 300 W
- voltage 0x24 = 36 V
- rpm 180 → 180·2.3129 m·60/1000 = 24.98 → **25.0 km/h**
- cadence 0x3C = 60
- flags 0x38 → calibrated, motor flag, second battery
- errors 0
- temperature 30
- odometer 0x64·500 = 50000 revolutions → **115.65 km**

## 5. Backend

The base URL `http://btplatform.keyde.com/api/` is set as `global.url` at L197257. I found **no call site that builds a request from it**: the fetch sites in app code are only the generic `fetchNetRepository` at L235746 and WebView/library code. Unverified: endpoints may be built in code I did not trace.

## 6. Open questions
- The variant-3 incoming frame length (assumed 40).
- Units of `foot_rpm` and temperature.
- What the error bits mean (the app never renders them).
- Whether bytes 9–17 of the outgoing frame carry anything on other firmware.
- Whether SIMAC is ever transmitted (see §2.3).
