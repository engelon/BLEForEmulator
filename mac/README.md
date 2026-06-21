# BLEForEmulator — Mac Bridge

The macOS menu bar app that provides a real Bluetooth radio to Android emulators running on the same machine.

---

## Architecture

```
NWListener (TCP :7877)
       │
       ▼
 SessionManager          ← routes commands ↔ events
    │          │
    ▼          ▼
BLECentralProxy     BLEPeripheralProxy
(CBCentralManager)  (CBPeripheralManager)
```

One `SessionManager` is created per connected emulator client. It owns both proxies and routes bidirectionally:

- Commands arriving over TCP → BLE operations on the proxy
- BLE delegate callbacks on the proxy → events sent over TCP

---

## Build

The runnable app is an **Xcode project**, not a Swift Package executable, because macOS entitlements and Info.plist embedding require a proper app bundle.

```
mac/BLEForEmulator/BLEForEmulator.xcodeproj
```

1. Open the project in Xcode.
2. Select the `BLEForEmulator` scheme.
3. Build & Run (⌘R).

The Swift source files under `mac/Sources/BLEForEmulatorMac/` are the canonical sources. The Xcode project at `mac/BLEForEmulator/BLEForEmulator/` contains copies — keep them in sync when editing.

---

## Required Configuration

### App Sandbox

**App Sandbox must be disabled.** With sandbox enabled, both TCP listening and Bluetooth access are blocked at the OS level.

In Xcode: Target → Signing & Capabilities → remove App Sandbox.

### Info.plist

The following keys must be present in the Xcode project's `Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>BLEForEmulator uses Bluetooth to relay BLE traffic for Android emulators.</string>

<key>LSUIElement</key>
<true/>
```

`LSUIElement = YES` hides the app from the Dock and makes it menu-bar-only.

### Bluetooth Permission

On first launch macOS will prompt for Bluetooth access. If the prompt does not appear, go to **System Settings → Privacy & Security → Bluetooth** and enable BLEForEmulator manually.

---

## TCP Server

- **Port:** 7877
- **Protocol:** newline-delimited JSON, one message per `\n`
- **Emulator host IP:** `10.0.2.2` (how the Android emulator reaches the Mac)

> Port 7877 was chosen to avoid conflict with the Android emulator's `netsimd` daemon, which uses port 7788.

---

## Source Files

| File | Purpose |
|---|---|
| `BLEForEmulatorApp.swift` | App entry point, `MenuBarExtra` scene |
| `MenuBarView.swift` | Status display, log scroll view, start/stop |
| `BridgeController.swift` | Top-level `ObservableObject`; owns TCPServer and sessions |
| `TCPServer.swift` | `NWListener`-based TCP server; emits `BridgeConnection` per client |
| `SessionManager.swift` | Routes commands → proxies, events → TCP per emulator session |
| `BLECentralProxy.swift` | `CBCentralManager` — scan, connect, GATT client |
| `BLEPeripheralProxy.swift` | `CBPeripheralManager` — advertise, GATT server |
| `Protocol.swift` | `BridgeCommand` / `BridgeEvent` JSON codec |

---

## Pending Scan / Advertise

Both proxies defer their first operation until `CBCentralManager` / `CBPeripheralManager` reports `.poweredOn`. Commands that arrive before Bluetooth is ready are queued and replayed automatically:

```
startScan arrives → BT not ready → stored in pendingScanUuids
BT powers on → centralManagerDidUpdateState(.poweredOn) → executeScan fires
```

---

## Characteristic Discovery

`didDiscoverServices` always triggers `discoverCharacteristics` on every service. `servicesDiscovered` is only emitted from `didDiscoverCharacteristicsFor` once all services have their characteristics populated. This avoids the race where `findCharacteristic` returns nil because characteristics were not yet fetched when `setNotify` / `writeCharacteristic` arrived.
