# BLEForEmulator Bridge Protocol

Version 1. The canonical machine-readable spec lives in [`shared/protocol.json`](../shared/protocol.json).

---

## Transport

- TCP, port **7877**
- One JSON object per line, delimited by `\n`
- The emulator connects; the Mac bridge listens
- The Mac sends `bridgeReady` immediately on accept

---

## Encoding

| Type | Encoding |
|---|---|
| Binary data | Base64 string |
| UUIDs | Uppercase hyphenated: `A1B2C3D4-E5F6-7890-ABCD-EF1234567890` |
| Addresses | CBPeripheral UUID string on macOS (e.g. `2AD28C65-...`) |

---

## Envelope

Every message is a flat JSON object. The discriminator is either `"command"` (emulator → Mac) or `"event"` (Mac → emulator).

```json
{ "command": "startScan", ... }
{ "event": "advertisementFound", ... }
```

An optional `"id"` field allows correlating commands with their response events.

---

## Commands (emulator → Mac)

### startScan

Begin scanning for BLE peripherals. Mac emits `advertisementFound` for each discovery.

```json
{
  "command": "startScan",
  "serviceUuids": ["A1B2C3D4-E5F6-7890-ABCD-EF1234567890"]
}
```

`serviceUuids` is optional. Omit to scan for all peripherals.

---

### stopScan

```json
{ "command": "stopScan" }
```

---

### connect

Connect to a peripheral by its address from `advertisementFound`.

```json
{
  "command": "connect",
  "id": "req-001",
  "address": "2AD28C65-1234-5678-ABCD-EF0123456789"
}
```

Mac emits `connected` on success or `connectionFailed` on failure.

---

### discoverServices

Discover all services and characteristics on a connected peripheral. Call after receiving `connected`.

```json
{
  "command": "discoverServices",
  "connectionId": "conn-abc123"
}
```

Mac emits `servicesDiscovered` once both services and their characteristics are fetched.

---

### readCharacteristic

```json
{
  "command": "readCharacteristic",
  "id": "req-002",
  "connectionId": "conn-abc123",
  "serviceUuid": "180A",
  "characteristicUuid": "2A29"
}
```

Mac emits `characteristicRead`.

---

### writeCharacteristic

```json
{
  "command": "writeCharacteristic",
  "id": "req-003",
  "connectionId": "conn-abc123",
  "serviceUuid": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
  "characteristicUuid": "B2C3D4E5-F6A7-8901-BCDE-F12345678901",
  "value": "eyJ0eXBlIjoiam9pbl9yZXF1ZXN0In0=",
  "withResponse": true
}
```

If `withResponse` is true, Mac emits `writeAcknowledged` when the peripheral confirms the write.

---

### setNotify

Subscribe to or unsubscribe from characteristic notifications.

```json
{
  "command": "setNotify",
  "connectionId": "conn-abc123",
  "serviceUuid": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
  "characteristicUuid": "B2C3D4E5-F6A7-8901-BCDE-F12345678901",
  "enable": true
}
```

When enabled, Mac emits `characteristicChanged` for each notification from the peripheral.

---

### advertise

Make the Mac advertise as a BLE peripheral on behalf of the emulator.

```json
{
  "command": "advertise",
  "serviceUuids": ["A1B2C3D4-E5F6-7890-ABCD-EF1234567890"],
  "localName": "MyDevice",
  "characteristics": [
    {
      "serviceUuid": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
      "characteristicUuid": "B2C3D4E5-F6A7-8901-BCDE-F12345678901",
      "properties": ["write", "notify"],
      "permissions": ["writeable"]
    }
  ]
}
```

Valid properties: `read`, `write`, `writeWithoutResponse`, `notify`, `indicate`.  
Valid permissions: `readable`, `writeable`.

Mac emits `connectionRequestReceived` when a central connects, and `characteristicWriteReceived` when a central writes.

---

### stopAdvertise

```json
{ "command": "stopAdvertise" }
```

---

### sendNotification

Push a notification to a subscribed central (used when emulator is acting as peripheral/host).

```json
{
  "command": "sendNotification",
  "connectionId": "central-xyz789",
  "serviceUuid": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
  "characteristicUuid": "B2C3D4E5-F6A7-8901-BCDE-F12345678901",
  "value": "eyJ0eXBlIjoiaGFuZG9mZiJ9"
}
```

`connectionId` is from the `connectionRequestReceived` event.

---

### disconnect

```json
{
  "command": "disconnect",
  "connectionId": "conn-abc123"
}
```

Mac emits `disconnected`.

---

## Events (Mac → emulator)

### bridgeReady

Sent immediately when a TCP client connects. Always wait for this before sending commands.

```json
{
  "event": "bridgeReady",
  "protocolVersion": 1,
  "platform": "macOS",
  "bluetoothState": "poweredOn"
}
```

`bluetoothState`: `poweredOn` | `poweredOff` | `unauthorized` | `unsupported`

---

### bluetoothStateChanged

```json
{
  "event": "bluetoothStateChanged",
  "bluetoothState": "poweredOff"
}
```

---

### advertisementFound

```json
{
  "event": "advertisementFound",
  "address": "2AD28C65-1234-5678-ABCD-EF0123456789",
  "localName": "TypeRaceHost",
  "rssi": -62,
  "serviceUuids": ["A1B2C3D4-E5F6-7890-ABCD-EF1234567890"],
  "serviceData": {}
}
```

May fire multiple times for the same peripheral. `localName` is optional.

---

### scanFailed

```json
{
  "event": "scanFailed",
  "error": "Bluetooth powered off"
}
```

---

### connected

```json
{
  "event": "connected",
  "id": "req-001",
  "connectionId": "conn-abc123",
  "address": "2AD28C65-1234-5678-ABCD-EF0123456789"
}
```

Use `connectionId` in all subsequent commands for this peripheral.

---

### connectionFailed

```json
{
  "event": "connectionFailed",
  "id": "req-001",
  "address": "2AD28C65-1234-5678-ABCD-EF0123456789",
  "error": "Peripheral not reachable"
}
```

---

### servicesDiscovered

```json
{
  "event": "servicesDiscovered",
  "connectionId": "conn-abc123",
  "services": [
    {
      "uuid": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
      "characteristics": [
        {
          "uuid": "B2C3D4E5-F6A7-8901-BCDE-F12345678901",
          "properties": ["write", "notify"]
        }
      ]
    }
  ]
}
```

Emitted only after all characteristics are discovered — safe to call `setNotify` / `writeCharacteristic` immediately on receipt.

---

### characteristicRead

```json
{
  "event": "characteristicRead",
  "id": "req-002",
  "connectionId": "conn-abc123",
  "characteristicUuid": "2A29",
  "value": "QXBwbGU="
}
```

---

### characteristicChanged

```json
{
  "event": "characteristicChanged",
  "connectionId": "conn-abc123",
  "characteristicUuid": "B2C3D4E5-F6A7-8901-BCDE-F12345678901",
  "value": "eyJ0eXBlIjoiaGFuZG9mZiJ9"
}
```

---

### writeAcknowledged

```json
{
  "event": "writeAcknowledged",
  "id": "req-003",
  "connectionId": "conn-abc123",
  "characteristicUuid": "B2C3D4E5-F6A7-8901-BCDE-F12345678901"
}
```

---

### connectionRequestReceived

A central connected to the peripheral advertised by the Mac on behalf of the emulator.

```json
{
  "event": "connectionRequestReceived",
  "connectionId": "central-xyz789"
}
```

---

### characteristicWriteReceived

```json
{
  "event": "characteristicWriteReceived",
  "connectionId": "central-xyz789",
  "serviceUuid": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
  "characteristicUuid": "B2C3D4E5-F6A7-8901-BCDE-F12345678901",
  "value": "eyJ0eXBlIjoiam9pbl9yZXF1ZXN0In0="
}
```

---

### disconnected

```json
{
  "event": "disconnected",
  "connectionId": "conn-abc123",
  "error": "Connection timeout"
}
```

`error` is omitted for clean disconnects.

---

## Flow Diagrams

### Central (emulator scans, connects, exchanges data)

```
emulator                          Mac bridge                     BLE peripheral
   │                                  │                                │
   │── startScan ──────────────────►  │                                │
   │                                  │── CBCentralManager.scan ──────►│
   │  ◄─────────────── advertisementFound ──────────────────────────── │
   │── stopScan ───────────────────►  │                                │
   │── connect ────────────────────►  │── CBCentralManager.connect ───►│
   │  ◄──────────────────── connected │◄── didConnect ─────────────────│
   │── discoverServices ───────────►  │── discoverServices ───────────►│
   │                                  │── discoverCharacteristics ─────►│
   │  ◄─────────── servicesDiscovered │◄── didDiscoverCharacteristics ─│
   │── setNotify (enable) ──────────► │── setNotifyValue ─────────────►│
   │── writeCharacteristic ─────────► │── writeValue ─────────────────►│
   │  ◄────────────── writeAcknowledged◄── didWriteValue ──────────────│
   │  ◄──────── characteristicChanged │◄── didUpdateValue (notify) ────│
   │── disconnect ──────────────────► │── cancelConnection ────────────►│
   │  ◄────────────────── disconnected│◄── didDisconnect ──────────────│
```

### Peripheral (emulator advertises, receives writes, sends notifications)

```
emulator                          Mac bridge                     BLE central
   │                                  │                                │
   │── advertise ──────────────────►  │── CBPeripheralManager.start ──►│
   │                                  │◄── central connects ───────────│
   │  ◄──── connectionRequestReceived │                                │
   │                                  │◄── central writes ─────────────│
   │  ◄──── characteristicWriteReceived                                │
   │── sendNotification ───────────►  │── updateValue ────────────────►│
   │── stopAdvertise ──────────────►  │── stopAdvertising ─────────────│
```
