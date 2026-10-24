# Installing and using Bike Battery

Source for the SideStore steps: docs.sidestore.io. On Windows, iloader needs iTunes; it is already installed on this PC.

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

## C. First ride
1. Open Bike Battery and leave it running (switch to Google Maps as normal).
2. Ride. You should hear "Bike battery N percent, about N kilometres" when it connects and each time it drops 10 %.
3. Afterwards, tell me whether you heard it and roughly how far you rode. I adjust the range estimate from the log.

## D. Weekly upkeep (30 seconds, once every 7 days)
Free Apple IDs make sideloaded apps stop opening after 7 days. To renew:
1. Open LocalDevVPN and tap Connect.
2. Open SideStore, go to My Apps, tap **Refresh All**.

If you forget, nothing is lost: the app just won't open until you refresh. (This can be automated later with an iOS Shortcut if it annoys you.)


## If refresh breaks
After an iOS update or reset, the pairing file can expire. Follow SideStore's "pairing file" guide.
