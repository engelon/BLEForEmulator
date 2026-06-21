# BLEForEmulator

**Real Bluetooth for the Android Emulator — no USB dongle, no Python stack, no hacks.**

The Android Emulator does not support Bluetooth. BLEForEmulator fixes that by routing BLE traffic from your emulator through your Mac's native Bluetooth radio, using a lightweight macOS menu bar app and a drop-in Android library.

---

## The Problem

If you build Android apps that use Bluetooth Low Energy, you need a physical device to test. The emulator's virtual Bluetooth controller cannot discover or connect to real peripherals. Existing workarounds require external USB Bluetooth dongles, a full Python Bluetooth stack (Bumble), sudo access, and a specific Android API level. That is a lot of friction for something that should just work.

---

## How It Works

BLEForEmulator has two parts:

**`mac/`** — a native Swift macOS menu bar app that uses CoreBluetooth to perform real BLE operations on behalf of the emulator. It runs a local TCP server on port **7877** and speaks a simple JSON protocol.

**`android/`** — a Kotlin library that wraps CoreBluetooth operations behind a clean API. Emulator detection is built in: on a real device the library is inert.

```
Android Emulator                         macOS
┌──────────────────┐                ┌──────────────────┐
│  Your BLE App    │                │   CoreBluetooth  │
│                  │                │   (real radio)   │
│  BLEBridge       │◄──── TCP ─────►│  BLEForEmulator  │
│  (drop-in lib)   │  10.0.2.2:7877 │  (menu bar app)  │
└──────────────────┘                └──────────────────┘
                                           │
                                        real BLE
                                           │
                                    iOS / BLE peripherals
```

The bridge protocol is a thin JSON envelope over newline-delimited TCP. It mirrors the standard BLE operation vocabulary — `startScan`, `connect`, `writeCharacteristic`, `advertisementFound`, `characteristicChanged` — so it is not tied to any specific BLE application protocol.

Both directions are supported. The emulator can act as a **scanner/client** (central) or as an **advertiser/host** (peripheral) — and switch between them within the same session.

---

## What Is Included

```
BLEForEmulator/
  mac/                 Swift — menu bar app, CoreBluetooth proxy, TCP server
  android/             Kotlin library — TCP transport, BLEBridge API
  shared/
    protocol.json      Machine-readable bridge message spec
  docs/
    protocol.md        Full message reference with JSON examples
```

---

## Quick Start

### 1. Build and run the Mac bridge

Open `mac/BLEForEmulator/BLEForEmulator.xcodeproj` in Xcode, build, and run. The app lives in the menu bar. Grant Bluetooth permission when prompted.

> See [`mac/README.md`](mac/README.md) for full setup instructions including required entitlements.

### 2. Add the Android library

Copy the source files from `android/lib/src/main/java/com/bleforemulator/` into your project (JitPack / Maven publishing coming soon).

Add the `INTERNET` permission to your `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

### 3. Use BLEBridge in your Android app

```kotlin
val bridge = BLEBridge()   // defaults to 10.0.2.2:7877

bridge.onEvent = { event ->
    when (event) {
        is BridgeEvent.BridgeReady         -> bridge.startScan(listOf(MY_SERVICE_UUID))
        is BridgeEvent.AdvertisementFound  -> bridge.connect(event.address)
        is BridgeEvent.Connected           -> bridge.discoverServices(event.connectionId)
        is BridgeEvent.ServicesDiscovered  -> { /* setNotify, writeCharacteristic */ }
        is BridgeEvent.CharacteristicChanged -> { /* handle notification */ }
        else -> {}
    }
}

bridge.connect()   // open TCP connection to Mac bridge
```

> See [`android/README.md`](android/README.md) for the full API and peripheral/host usage.

---

## Requirements

- macOS 13+ with Bluetooth hardware
- Android API 26+
- Android Emulator (any recent version)
- Mac and emulator on the same machine (the emulator reaches the host at `10.0.2.2`)

---

## Limitations

- BLEForEmulator is a **development tool**. Use `debugImplementation` to keep it out of production builds.
- The bridge adds a TCP hop. Timing-sensitive BLE flows may behave slightly differently than on real hardware. Treat emulator tests as fast feedback, not a substitute for real-device validation.
- One emulator client per bridge instance. Multi-emulator support is planned.
- macOS only. A Windows bridge app is not currently planned.

---

## Protocol Summary

All messages are JSON objects, one per line (`\n` delimiter). Binary values are base64-encoded. UUIDs are uppercase hyphenated.

**Commands (emulator → Mac):**

| Command | Description |
|---|---|
| `startScan` | Scan for peripherals matching optional service UUIDs |
| `stopScan` | Stop scanning |
| `connect` | Connect to a peripheral by address |
| `discoverServices` | Discover services and characteristics |
| `readCharacteristic` | Read a characteristic value |
| `writeCharacteristic` | Write a value (with or without response) |
| `setNotify` | Subscribe/unsubscribe to notifications |
| `advertise` | Advertise as a BLE peripheral (emulator as host) |
| `stopAdvertise` | Stop advertising |
| `sendNotification` | Push a notification to a subscribed central |
| `disconnect` | Disconnect from a peripheral |

**Events (Mac → emulator):**

| Event | Description |
|---|---|
| `bridgeReady` | Sent on TCP connect — confirms bridge is alive |
| `bluetoothStateChanged` | Mac Bluetooth was toggled on or off |
| `advertisementFound` | Peripheral discovered during scan |
| `connected` | Connection established |
| `connectionFailed` | Connection attempt failed |
| `servicesDiscovered` | Service + characteristic discovery complete |
| `characteristicRead` | Read result |
| `characteristicChanged` | Notification/indication received |
| `writeAcknowledged` | Write-with-response confirmed |
| `connectionRequestReceived` | A central connected to the bridge peripheral |
| `characteristicWriteReceived` | Central wrote to a characteristic (emulator as host) |
| `disconnected` | Peripheral disconnected |

See [`docs/protocol.md`](docs/protocol.md) for full message schemas and flow diagrams.

---

## Roadmap

- [ ] JitPack / Maven publishing for the Android library
- [ ] Multi-emulator support
- [ ] Bonding and pairing flow support
- [ ] Linux bridge app
- [ ] Automated integration test harness

---

## Real-World Usage

BLEForEmulator was built to support development of [NearbyDiscoveryKit](../README.md), a cross-platform BLE proximity discovery framework for iOS and Android. NearbyDiscoveryKit uses BLEForEmulator to test the full iOS ↔ Android handoff without requiring a physical Android device during development.

---

## License

MIT. See [LICENSE](LICENSE).
