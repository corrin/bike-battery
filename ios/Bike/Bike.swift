import AVFoundation
import CoreBluetooth

/// Listens to a BLE-MOTOR controller (read-only: never writes) and speaks the battery level.
final class Bike: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate, AVSpeechSynthesizerDelegate {
    static let service = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let notify = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

    @Published var state = "Starting Bluetooth"
    @Published var status: Status?
    /// Lowest voltage seen at < 100 W since connecting, like the official app's set_dianchi; ignores sag under load.
    @Published var restingV: Int?
    @Published var notifications: [String] = []

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var buf: [UInt8] = []
    private var lastBand: Int?
    private let voice = AVSpeechSynthesizer()

    var settings: Settings {
        let d = UserDefaults.standard
        return Settings(fullV: d.double(forKey: "fullV"), emptyV: d.double(forKey: "emptyV"), kmPerCharge: d.double(forKey: "kmPerCharge"))
    }

    override init() {
        super.init()
        UserDefaults.standard.register(defaults: ["fullV": 42.0, "emptyV": 32.0, "kmPerCharge": 40.0])
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        voice.delegate = self
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func say() {
        try? AVAudioSession.sharedInstance().setActive(true)
        voice.speak(AVSpeechUtterance(string: restingV.map { summary(volts: $0, settings) } ?? "Bike battery unknown."))
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        // Un-duck Google Maps / music.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Central

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        guard c.state == .poweredOn else { state = "Bluetooth unavailable"; return }
        state = "Looking for BLE-MOTOR"
        c.scanForPeripherals(withServices: nil)
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData ad: [String: Any], rssi: NSNumber) {
        let name = ((ad[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? "").uppercased()
        guard name == "BLE-MOTOR" || name == "BLE_MOTOR" else { return }
        c.stopScan()
        peripheral = p
        p.delegate = self
        state = "Connecting"
        c.connect(p)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        state = "Connected, finding service"
        restingV = nil
        lastBand = nil
        buf = []
        p.discoverServices([Self.service])
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        state = "Disconnected, waiting for bike"
        status = nil
        c.connect(p) // never times out; completes when the bike is back in range
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        state = "Connect failed, retrying"
        c.connect(p)
    }

    // MARK: Peripheral

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = p.services?.first(where: { $0.uuid == Self.service }) else {
            state = "Bike has no Nordic UART service (different controller variant?)"
            return
        }
        p.discoverCharacteristics([Self.notify], for: s)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        guard let ch = s.characteristics?.first(where: { $0.uuid == Self.notify }) else {
            state = "Bike has no 6E400003 characteristic"
            return
        }
        p.setNotifyValue(true, for: ch)
        state = "Listening"
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.state == "Listening", self.status == nil else { return }
            self.state = "Connected, but the bike sends nothing (it may need the official app's init frame)"
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let data = ch.value else { return }
        notifications = Array(([data.map { String(format: "%02X", $0) }.joined(separator: " ")] + notifications).prefix(50))
        buf += data
        for f in takeFrames(&buf) {
            let s = parseStatus(f)
            status = s
            state = "Receiving"
            if s.powerW < 100, s.volts > 0 { restingV = min(restingV ?? s.volts, s.volts) }
        }
        guard let v = restingV else { return }
        let band = batteryPercent(volts: v, settings) / 10
        if let last = lastBand, band >= last { return }
        lastBand = band
        say()
    }
}
