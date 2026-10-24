# Plan: e-bike battery announcer alongside Google Maps (iPhone 16e)

## Context
Use the real Google Maps app unchanged for navigation, and add only what the phone can't know: the e-bike's battery and remaining range. Write as little code as possible, and pay nothing to install it.

From the decompile (`docs/protocol.md`, `tools/frames.py`):
- The bike (`BLE-MOTOR`, Nordic UART) pushes status frames on `6E400003`.
- The only battery information in them is whole-volt pack voltage (byte 3, or byte 15 if the second-battery flag is set).
- The bike sends no range; we estimate it.
- Writing to the bike means sending all its settings, so v1 never writes.

## Decisions (mine to make, stated so they can be overruled)
- **Install route: SideStore + GitHub Actions.** It's free and needs no Xcode on the Mac. The initial install works from the Windows PC or the Mac (per docs.sidestore.io prerequisites; Windows needs iTunes). After that, everything happens on the phone. The alternative, Xcode free provisioning, means a weekly USB re-install from a Mac with Xcode kept installed, which rules it out given the Mac's disk space.
  - Weekly upkeep: connect the LocalDevVPN app, open SideStore and tap refresh. An iOS Shortcuts automation can make that one tap.
- **Display v1: spoken announcements** mixed with Google Maps' voice, plus a plain in-app status screen. The floating Picture-in-Picture box (`UIPiPView`) is deferred until rides show a visual is wanted.
- **Read-only:** v1 never writes to the bike.
- **Repo:** private GitHub repo. The free plan includes 2,000 Actions minutes a month; macOS runners count at 10×, giving about 200 macOS minutes, or roughly 25 builds a month.
  - Excluded from git: `apk/`, `extracted/`, `decompiled/`, `.venv/` (third-party code).

## Phase 0: garage check (user, about 5 min, no code). Gates the BLE code.
Run the nRF Connect steps already given. Results needed:
1. The advertised name.
2. Whether frames arrive without writing anything.
3. Sample hex values.
4. The pack's voltage rating from its label.

If no frames arrive, stop and re-plan: the app would have to send the settings frame, built from the official app's current settings read off the tablet.

## Phase 1: app + pipeline (me)
Files (all new):
- `.gitignore`
- `ios/project.yml`: XcodeGen spec.
  - iOS 17 deployment target, `SWIFT_VERSION 5`, generated Info.plist.
  - `NSBluetoothAlwaysUsageDescription`.
  - `UIBackgroundModes: [bluetooth-central, audio]`.
- `ios/Bike/Frame.swift`: pure Foundation, no UIKit. A port of `tools/frames.py` `verify()` and `parse_status()`, battery fields only.
  - Find frames in a byte buffer: start at `0x55`, try lengths 40 then 20, validate the checksum. This handles notifications split across packets.
  - Battery % is linear between the empty and full voltages.
  - Only voltage seen while power < 100 W is used, and the lowest such reading is latched (copied from the official app's `set_dianchi`). This stops voltage sag and recovery from flapping the number.
  - Range = % × km-per-charge.
- `ios/Bike/Bike.swift`: CoreBluetooth central.
  - Scan for name `BLE-MOTOR`/`BLE_MOTOR`, connect, subscribe to `6E400003`, auto-reconnect.
  - Keep the last 50 hex frames for the debug view.
  - If no frame arrives within 10 s, set state to "connected but bike sends nothing".
  - Announce via `AVSpeechSynthesizer` when the latched percent drops a band (10 %), plus once on connect. Audio session: `.playback` with `.duckOthers` / `.interruptSpokenAudioAndMixWithOthers`.
- `ios/Bike/App.swift`: one SwiftUI screen.
  - Shows state, volts, %, range, a "Say it now" button and the raw-frame list.
  - Settings via `@AppStorage`: full V, empty V, km per charge. Defaults come from the pack's nominal voltage: cells = nominal/3.6, full = cells × 4.2, empty = cells × 3.2.
- `ios/selftest/main.swift`: assert checks using the test vectors from `tools/frames.py` `__main__`, plus the real captured frames from phase 0.
- `.github/workflows/ios.yml` on a `macos-15` runner. Steps:
  1. `swiftc Frame.swift selftest/main.swift` and run the result.
  2. `brew install xcodegen`, then `xcodegen`.
  3. `xcodebuild -sdk iphoneos CODE_SIGNING_ALLOWED=NO`.
  4. Zip `Payload/*.app` into `BikeBattery.ipa`.
  5. Attach the `.ipa` to a GitHub Release so it's easy to find on the phone.
- `docs/install.md`: phone setup and update steps.

Needs the user's OK before running: creating the private GitHub repo and pushing (`gh repo create --private`).

## Phase 2: install (user, guided by `docs/install.md`)
1. Follow the SideStore install: iloader on the PC or Mac, LocalDevVPN on the phone, Developer Mode on, trust the profile.
2. On the iPhone in Safari: open the repo's Releases page, download `BikeBattery.ipa`, then use Share → SideStore (or SideStore → **+**) to install. (Exact handoff unverified; docs/install.md gets corrected after the first try.)

## Phase 3: ride test
- Check that announcements play while Google Maps is in front and the screen is locked.
  - Risk: speaking from the background depends on the audio session staying active.
- Calibrate the full voltage after a charge, and km per charge after a few rides.

## Considered and parked: our own app with Google navigation inside it
The Google Navigation SDK for iOS embeds Google's turn-by-turn guidance, including cycling, inside our app. We could then draw the battery on top natively, with no hack.
- **Cost:** pay-as-you-go. The first 1,000 destinations a month are free and guidance and reroutes aren't billed, but it still needs a Google Cloud billing account with a card. Some pages say it's "available only to some customers".
- **Losses:** saved places, history and voice search, plus new Google Maps features as Google adds them. We'd also need a destination search screen.
- **Apple MapKit is out:** it has no in-app cycling directions, only a handoff to Apple Maps.
- **Revisit** if announcements and the PiP box both prove inadequate.

## Later, only if wanted
- The floating PiP box (`UIPiPView`, pinned to `55994ac`).
- Gear buttons, after reading the current settings from the official app.

## Verification
- **CI:** the selftest asserts pass, including real frames from phase 0, and the build produces the `.ipa`.
- **Phone:** the app installs via SideStore, the debug list shows frames from the bike, and the voltage matches what's expected for the pack.
- **Ride:** with Google Maps navigating and the phone locked, at least one battery announcement is heard, and it reconnects after the bike is power-cycled.
