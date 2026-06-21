# BLEForEmulator — Android Library

Kotlin library that gives Android emulators real Bluetooth by routing BLE operations through the Mac bridge over TCP.

---

## Setup

### 1. Copy sources

Until JitPack / Maven publishing is available, copy the four source files into your project:

```
android/lib/src/main/java/com/bleforemulator/
  BLEBridge.kt          ← public entry point
  BridgeProtocol.kt     ← command/event codec
  BridgeTCPClient.kt    ← TCP transport (background thread)
  EmulatorDetector.kt   ← detects AVD / Genymotion
```

No external dependencies — the library uses `java.net` sockets and Android's built-in `org.json`.

### 2. Manifest permission

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

This is required for the TCP connection to `10.0.2.2:7877`. The permission is low-risk and does not require runtime approval.

### 3. minSdk

The library requires `minSdk = 26` (Android 8.0).

---

## API

### BLEBridge

The main entry point. All operations are fire-and-forget; results arrive via `onEvent`.

```kotlin
val bridge = BLEBridge()                   // default: 10.0.2.2:7877
// val bridge = BLEBridge("10.0.2.2", 7877) // explicit

bridge.onEvent      = { event -> /* handle on background thread */ }
bridge.onDisconnect = { /* TCP connection dropped */ }

bridge.connect()   // open TCP connection — call once
```

> Callbacks arrive on a background thread. Post to `Dispatchers.Main` or `Handler(Looper.getMainLooper())` before touching UI.

---

### Emulator detection

```kotlin
bridge.isEmulator()        // true on AVD or Genymotion
EmulatorDetector.isEmulator()  // static, same check
```

Use this to conditionally activate the bridge in your app:

```kotlin
if (EmulatorDetector.isEmulator()) {
    val bridge = BLEBridge()
    // use bridge for BLE
} else {
    // use standard Android BLE APIs
}
```

---

### Central (scanner / client) flow

```kotlin
bridge.onEvent = { event ->
    when (event) {
        is BridgeEvent.BridgeReady -> {
            // Always wait for BridgeReady before sending any commands.
            bridge.startScan(listOf("A1B2C3D4-E5F6-7890-ABCD-EF1234567890"))
        }
        is BridgeEvent.AdvertisementFound -> {
            bridge.stopScan()
            bridge.connect(event.address)
        }
        is BridgeEvent.Connected -> {
            bridge.discoverServices(event.connectionId)
        }
        is BridgeEvent.ServicesDiscovered -> {
            val cid = event.connectionId
            bridge.setNotify(cid, SERVICE_UUID, CHAR_UUID, true)
            bridge.writeCharacteristic(cid, SERVICE_UUID, CHAR_UUID, payload)
        }
        is BridgeEvent.CharacteristicChanged -> {
            val data = event.value   // ByteArray
            bridge.disconnectPeripheral(event.connectionId)
        }
        is BridgeEvent.Disconnected -> { /* done */ }
        else -> {}
    }
}

bridge.connect()
```

---

### Peripheral (advertiser / host) flow

```kotlin
bridge.onEvent = { event ->
    when (event) {
        is BridgeEvent.BridgeReady -> {
            bridge.startAdvertising(
                serviceUuids = listOf(SERVICE_UUID),
                localName    = "MyDevice",
                characteristics = listOf(
                    AdvertiseCharacteristic(
                        serviceUuid        = SERVICE_UUID,
                        characteristicUuid = CHAR_UUID,
                        properties         = listOf("write", "notify"),
                        permissions        = listOf("writeable")
                    )
                )
            )
        }
        is BridgeEvent.ConnectionRequestReceived -> {
            // a central connected — store event.connectionId
        }
        is BridgeEvent.CharacteristicWriteReceived -> {
            val payload = event.value   // ByteArray
            // respond via notification
            bridge.sendNotification(event.connectionId, SERVICE_UUID, CHAR_UUID, response)
        }
        else -> {}
    }
}

bridge.connect()
```

---

### BridgeEvent types

| Type | Key fields |
|---|---|
| `BridgeEvent.BridgeReady` | `protocolVersion`, `bluetoothState` |
| `BridgeEvent.BluetoothStateChanged` | `state` |
| `BridgeEvent.AdvertisementFound` | `address`, `localName`, `rssi`, `serviceUuids` |
| `BridgeEvent.Connected` | `connectionId`, `address` |
| `BridgeEvent.ConnectionFailed` | `address`, `error` |
| `BridgeEvent.ServicesDiscovered` | `connectionId`, `services` |
| `BridgeEvent.CharacteristicRead` | `connectionId`, `characteristicUuid`, `value: ByteArray` |
| `BridgeEvent.CharacteristicChanged` | `connectionId`, `characteristicUuid`, `value: ByteArray` |
| `BridgeEvent.WriteAcknowledged` | `connectionId`, `characteristicUuid` |
| `BridgeEvent.ConnectionRequestReceived` | `connectionId` |
| `BridgeEvent.CharacteristicWriteReceived` | `connectionId`, `serviceUuid`, `characteristicUuid`, `value: ByteArray` |
| `BridgeEvent.Disconnected` | `connectionId`, `error?` |

---

## Important: wait for BridgeReady

The TCP connection is asynchronous. Sending commands before `BridgeReady` is received will silently fail because the Mac bridge may not yet have processed the connection. Always gate your first command on `BridgeReady`:

```kotlin
// ❌ Wrong — startScan fires before TCP handshake completes
bridge.connect()
bridge.startScan(...)

// ✅ Correct — wait for BridgeReady
bridge.onEvent = { event ->
    if (event is BridgeEvent.BridgeReady) bridge.startScan(...)
}
bridge.connect()
```

---

## Port

Default port is **7877**. This was chosen to avoid conflict with the Android emulator's `netsimd` daemon, which runs on port 7788 and will intercept TCP connections to that port.

---

## Thread safety

`BridgeTCPClient.send()` dispatches each write on a new daemon thread. `onEvent` callbacks are delivered on the read thread. If you hold mutable state accessed from both `onEvent` and the main thread, synchronize it yourself.
