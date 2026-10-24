import SwiftUI

@main
struct BikeBatteryApp: App {
    @StateObject private var bike = Bike()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup { ContentView(bike: bike) }
            .onChange(of: phase) { if phase == .background { bike.upload() } }
    }
}

struct ContentView: View {
    @ObservedObject var bike: Bike
    @AppStorage("fullV") private var fullV = 42.0
    @AppStorage("emptyV") private var emptyV = 32.0
    @AppStorage("kmPerCharge") private var kmPerCharge = 40.0

    var body: some View {
        NavigationStack {
            Form {
                Section("Bike") {
                    Text(bike.state)
                    if let v = bike.restingV {
                        let s = Settings(fullV: fullV, emptyV: emptyV, kmPerCharge: kmPerCharge)
                        LabeledContent("Battery", value: "\(batteryPercent(volts: v, s)) % · ~\(rangeKm(volts: v, s)) km (\(v) V resting)")
                    }
                    if let s = bike.status {
                        LabeledContent("Now", value: "\(s.volts) V · \(s.powerW) W")
                    }
                    Button("Say it now") { bike.say() }
                }
                Section {
                    field("Full voltage", $fullV)
                    field("Empty voltage", $emptyV)
                    field("km per full charge", $kmPerCharge)
                } header: {
                    Text("Settings")
                } footer: {
                    Text("Full ≈ nominal × 1.17, empty ≈ nominal × 0.89. A 36 V pack is about 42 / 32.")
                }
            }
            .navigationTitle("Bike Battery")
        }
    }

    private func field(_ label: String, _ value: Binding<Double>) -> some View {
        LabeledContent(label) {
            TextField(label, value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }
}
