# Installing Bike Battery on the iPhone (free, no Xcode)

Source for the SideStore steps: docs.sidestore.io (prerequisites + install). Re-check there if something differs.

## One time: SideStore
1. Phone: set a passcode if you don't have one. Install **LocalDevVPN** from the App Store.
2. Computer (Windows PC or Mac). On Windows, first install **iTunes** (Microsoft Store or Apple).
3. Install **iloader** on that computer.
4. Plug in the iPhone over USB. Tap **Trust** on the phone and enter your passcode.
5. In iloader: sign in with your Apple ID (the password is case-sensitive), select the phone, then **Install SideStore (Stable)**.
6. Phone: **Settings → General → VPN & Device Management**. Under Developer App, tap your Apple ID and **Trust** it.
7. Phone: **Settings → Privacy & Security → Developer Mode → On**. The phone restarts.
8. Open **LocalDevVPN** and tap **Connect**.
9. Open **SideStore** and sign in with the same Apple ID. Then go to **My Apps** and tap the **7 DAYS** counter next to SideStore. If it asks to revoke or create a certificate, tap Yes.

## Each new build
1. Phone, Safari: open the GitHub repo → **Releases** → latest **Build N** → tap **BikeBattery.ipa** to download it.
2. Connect **LocalDevVPN**.
3. In **SideStore → My Apps**, tap **+** and pick `BikeBattery.ipa` from Downloads.
   *(Unverified: you may also be able to use Share → SideStore from the download. Update this file after the first try.)*
4. First launch: allow Bluetooth.

## Weekly (apps expire after 7 days on a free Apple ID)
Connect **LocalDevVPN**, open **SideStore → My Apps**, then tap the days counter or **Refresh All**.

## If refresh breaks
After an iOS update or reset, the pairing file can expire. Follow SideStore's "pairing file" guide.
