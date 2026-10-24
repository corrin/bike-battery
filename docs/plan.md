# Bike Battery: every step from now to riding with it

## Context
The goal: while riding with Google Maps, the iPhone speaks the e-bike's battery % and range, which Google Maps can't know. Our app does only that and leaves Google Maps alone.

What exists now:
- The app is written and builds automatically on GitHub (Build 3 at github.com/corrin/bike-battery/releases). It has not yet run on a phone.
- The app logs everything it sees and sends the log to me automatically. You never handle logs.
- This PC already has iTunes, which the installer needs on Windows. Nothing new from Apple needs installing.

**One small code change before we start (me):** make the log upload happen the moment you leave the app. It already does that, and the 5-minute timer stays as a backup. That way, no step below involves waiting a set number of minutes.

## A. One-time setup (about 20 min, at your desk; no bike needed)
On the **iPhone**:
1. If the phone has no passcode, set one (Settings → Face ID & Passcode).
2. App Store: install **LocalDevVPN** (apps.apple.com/app/localdevvpn/id6755608044).

On **this PC**:
3. Download and run **iloader**: github.com/nab138/iloader/releases/latest/download/iloader-windows-x64.msi
4. Plug the iPhone in with a USB cable. When the phone asks "Trust this computer?", tap **Trust** and enter your passcode.
5. In iloader:
   - Sign in with your Apple ID (the password is case-sensitive).
   - Select the iPhone.
   - Click **Install SideStore (Stable)**.
   - Unplug when it's done. The cable is never needed again.

On the **iPhone**:

6. Settings → General → **VPN & Device Management**. Under "Developer App", tap your Apple ID and tap **Trust**.
7. Settings → Privacy & Security → **Developer Mode** → On. The phone restarts and asks you to confirm.
8. Open **LocalDevVPN** and tap **Connect**.
9. Open **SideStore** and sign in with the same Apple ID. Go to **My Apps** and tap the **7 DAYS** label next to SideStore. If it asks about a certificate, tap Yes.
10. In Safari, go to **github.com/corrin/bike-battery/releases**. Under the newest Build, tap **BikeBattery.ipa** and confirm the download.
11. In SideStore, go to **My Apps**, tap **+**, then pick BikeBattery.ipa (in Downloads).
12. Open **Bike Battery** and tap **Allow** for Bluetooth. You'll see "Looking for BLE-MOTOR". Close it. Setup is done.

If any screen doesn't match these steps, send me a screenshot or a description and I'll correct `docs/install.md`.

## B. First bike check (about 2 min, at the bike)
1. Turn the bike on.
2. Open **Bike Battery** and watch the top line. Within about a minute it will show one of:
   - **"Receiving"**: it works, and a Battery line appears.
   - **"Connected, but the bike sends nothing…"**: the bike needs a wake-up message. I'd handle that next.
   - **"Looking for BLE-MOTOR"** that never changes: the bike's name is different. The log shows me the real name.
3. Close the app (swipe home). The log uploads as you do.
4. Tell me which message you saw. I read the log myself.

## C. What I do after B
- **"Receiving":** check the voltage readings against your pack, set sensible full and empty voltages, and push a new build if anything needs fixing.
- **"Sends nothing" or a wrong name:** work out the fix from the log and tell you exactly what changes before building anything. A wake-up message would mean writing to the bike, and I won't do that without your OK.
- **New builds:** repeat A10–A11 only (download, then SideStore +).

## D. First ride
1. Open Bike Battery and leave it running (switch to Google Maps as normal).
2. Ride. You should hear "Bike battery N percent, about N kilometres" when it connects and each time it drops 10 %.
3. Afterwards, tell me whether you heard it and roughly how far you rode. I adjust the range estimate from the log.

## E. Weekly upkeep (30 seconds, once every 7 days)
Free Apple IDs make sideloaded apps stop opening after 7 days. To renew:
1. Open LocalDevVPN and tap Connect.
2. Open SideStore, go to My Apps, tap **Refresh All**.

If you forget, nothing is lost: the app just won't open until you refresh. (This can be automated later with an iOS Shortcut if it annoys you.)

## Not planned unless you ask
- An on-screen floating box over Google Maps.
- Gear up/down buttons. These need writes to the bike.
- Ride history.

## Verification (mine)
- **CI:** stays green with the self-tests passing.
- **After B:** the log appears via ntfy.sh, and I confirm what the bike sent.
- **After D:** the log shows SAY lines, so announcements fired. You confirm you heard them.
