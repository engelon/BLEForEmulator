# Contributing to BLEForEmulator

## Dev Setup

### Mac bridge

1. Open `mac/BLEForEmulator/BLEForEmulator.xcodeproj` in Xcode 15+.
2. Ensure App Sandbox is **off** (Signing & Capabilities).
3. Build & Run. The app appears in the menu bar.
4. On first run, grant Bluetooth permission when prompted.

Edit the canonical sources in `mac/Sources/BLEForEmulatorMac/` and copy changes into the Xcode project copies at `mac/BLEForEmulator/BLEForEmulator/`.

### Android library

1. Open `android/` in Android Studio.
2. The `:lib` module is the library; there is no sample app in this repo.
3. To test, copy the library source into a project that has an Android emulator AVD configured.

### Integration testing

The full test loop:

1. Start the Mac bridge from Xcode.
2. Boot an Android emulator AVD.
3. Run an Android app that uses `BLEBridge` (e.g. the NearbyDiscoveryKit demo app).
4. Run an iOS app on a physical device or simulator (if your Mac has BT) that acts as the BLE peripheral.
5. Observe the bridge log in the menu bar for the full handshake.

## Protocol changes

The protocol spec lives in `shared/protocol.json`. If you add a new command or event:

1. Update `shared/protocol.json`.
2. Update `mac/Sources/BLEForEmulatorMac/Protocol.swift` — add the case to `BridgeCommand` or `BridgeEvent` and implement JSON encode/decode.
3. Update `android/lib/src/main/java/com/bleforemulator/BridgeProtocol.kt` — same.
4. Update `android/lib/src/main/java/com/bleforemulator/BLEBridge.kt` if a new public method is needed.
5. Update `docs/protocol.md`.

Both sides must be updated together; there is no versioned negotiation beyond `protocolVersion` in `bridgeReady`.

## Code style

- Swift: standard Swift API design guidelines, no forced unwraps on the hot path.
- Kotlin: standard Kotlin idioms, coroutines are not used (plain threads + callbacks for minimal dependencies).
- TODOs in code mark known limitations — leave them, do not silently remove them without implementing the feature.

## Pull requests

- Keep PRs focused. A PR that fixes a bug and adds a feature is two PRs.
- Test with a real emulator + real peripheral before opening. Simulator-only testing misses the Bluetooth layer.
- Update docs if the public API or protocol changes.
