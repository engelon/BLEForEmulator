package com.bleforemulator

/**
 * BLEBridge — public entry point for BLEForEmulator.
 *
 * Usage:
 *   val bridge = BLEBridge()
 *   bridge.onEvent = { event -> /* handle on any thread */ }
 *   bridge.connect()
 *
 *   bridge.startScan(listOf("A1B2C3D4-E5F6-7890-ABCD-EF1234567890"))
 *   // ... wait for AdvertisementFound events ...
 *   bridge.connect(address)
 *   // ... wait for Connected, then discoverServices, etc.
 *
 * All commands are fire-and-forget; responses arrive via onEvent.
 * Callbacks are invoked on a background thread — post to main thread if updating UI.
 */
class BLEBridge(
    host: String = "10.0.2.2",
    port: Int    = 7877
) {
    /** Receive all events from the Mac bridge here. */
    var onEvent: ((BridgeEvent) -> Unit)? = null

    /** Called when the TCP connection drops. */
    var onDisconnect: (() -> Unit)? = null

    private val client = BridgeTCPClient(host, port)

    init {
        client.onEvent      = { event -> onEvent?.invoke(event) }
        client.onDisconnect = { onDisconnect?.invoke() }
    }

    // MARK: - Lifecycle

    /** Open the TCP connection to the Mac bridge. Call once on startup. */
    fun connect() = client.connect()

    /** Close the TCP connection. */
    fun disconnect() = client.disconnect()

    // MARK: - Central (scanner/client) operations

    fun startScan(serviceUuids: List<String> = emptyList()) =
        client.send(BridgeCommand.StartScan(serviceUuids))

    fun stopScan() = client.send(BridgeCommand.StopScan)

    /** address comes from AdvertisementFound.address */
    fun connect(address: String, id: String? = null) =
        client.send(BridgeCommand.Connect(address, id))

    /** Call after Connected event. */
    fun discoverServices(connectionId: String) =
        client.send(BridgeCommand.DiscoverServices(connectionId))

    fun readCharacteristic(connectionId: String, serviceUuid: String, characteristicUuid: String, id: String? = null) =
        client.send(BridgeCommand.ReadCharacteristic(connectionId, serviceUuid, characteristicUuid, id))

    fun writeCharacteristic(connectionId: String, serviceUuid: String, characteristicUuid: String, value: ByteArray, withResponse: Boolean = true, id: String? = null) =
        client.send(BridgeCommand.WriteCharacteristic(connectionId, serviceUuid, characteristicUuid, value, withResponse, id))

    fun setNotify(connectionId: String, serviceUuid: String, characteristicUuid: String, enable: Boolean) =
        client.send(BridgeCommand.SetNotify(connectionId, serviceUuid, characteristicUuid, enable))

    fun disconnectPeripheral(connectionId: String) =
        client.send(BridgeCommand.Disconnect(connectionId))

    // MARK: - Peripheral (advertiser/host) operations

    fun startAdvertising(
        serviceUuids:    List<String>,
        localName:       String?                    = null,
        characteristics: List<AdvertiseCharacteristic> = emptyList()
    ) = client.send(BridgeCommand.Advertise(serviceUuids, localName, characteristics))

    fun stopAdvertising() = client.send(BridgeCommand.StopAdvertise)

    /** Send a BLE notification to a subscribed central. connectionId from ConnectionRequestReceived. */
    fun sendNotification(connectionId: String, serviceUuid: String, characteristicUuid: String, value: ByteArray) =
        client.send(BridgeCommand.SendNotification(connectionId, serviceUuid, characteristicUuid, value))

    // MARK: - Utility

    /** True when running on an AVD or Genymotion emulator. */
    fun isEmulator(): Boolean = EmulatorDetector.isEmulator()
}
