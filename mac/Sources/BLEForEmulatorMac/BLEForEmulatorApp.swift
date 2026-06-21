import SwiftUI

@main
struct BLEForEmulatorApp: App {
    @StateObject private var bridge = BridgeController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(bridge)
        } label: {
            Label("BLEForEmulator", systemImage: bridge.isListening ? "bluetooth" : "bluetooth.slash")
        }
        .menuBarExtraStyle(.window)
    }
}
