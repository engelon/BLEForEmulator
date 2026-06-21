import Foundation

// MARK: - SessionManager
// One instance per connected emulator client.
// Routes commands from TCP → BLE proxies, and BLE events → TCP.

final class SessionManager {

    private let connection:      BridgeConnection
    private let centralProxy:    BLECentralProxy    = BLECentralProxy()
    private let peripheralProxy: BLEPeripheralProxy = BLEPeripheralProxy()

    var onLog: ((String) -> Void)?

    init(connection: BridgeConnection) {
        self.connection = connection
        setup()
    }

    // MARK: - Setup

    private func setup() {
        // Route BLE events → TCP
        centralProxy.onEvent    = { [weak self] in self?.send($0) }
        peripheralProxy.onEvent = { [weak self] in self?.send($0) }

        // Route TCP commands → BLE proxies
        connection.onCommand = { [weak self] command in
            self?.handle(command)
        }

        // Greet the emulator
        send(.bridgeReady(bluetoothState: "poweredOn"))
        // TODO: read actual Bluetooth state from CBCentralManager before sending bridgeReady
    }

    // MARK: - Command routing

    private func handle(_ command: BridgeCommand) {
        switch command {

        // Central (scanner/client) operations
        case .startScan(let uuids):
            log("startScan \(uuids)")
            centralProxy.startScan(serviceUuids: uuids)

        case .stopScan:
            log("stopScan")
            centralProxy.stopScan()

        case .connect(let address, let id):
            log("connect \(address)")
            centralProxy.connect(address: address, id: id)

        case .discoverServices(let cid):
            centralProxy.discoverServices(connectionId: cid)

        case .readCharacteristic(let cid, let svc, let chr, let id):
            centralProxy.readCharacteristic(connectionId: cid, serviceUuid: svc, characteristicUuid: chr, id: id)

        case .writeCharacteristic(let cid, let svc, let chr, let value, let withResponse, let id):
            centralProxy.writeCharacteristic(connectionId: cid, serviceUuid: svc, characteristicUuid: chr, value: value, withResponse: withResponse, id: id)

        case .setNotify(let cid, let svc, let chr, let enable):
            centralProxy.setNotify(connectionId: cid, serviceUuid: svc, characteristicUuid: chr, enable: enable)

        case .disconnect(let cid):
            log("disconnect \(cid)")
            centralProxy.disconnect(connectionId: cid)

        // Peripheral (advertiser/host) operations
        case .advertise(let uuids, let name, let chars):
            log("advertise \(uuids)")
            peripheralProxy.startAdvertising(serviceUuids: uuids, localName: name, advertiseChars: chars)

        case .stopAdvertise:
            log("stopAdvertise")
            peripheralProxy.stopAdvertising()

        case .sendNotification(let cid, _, let chr, let value):
            peripheralProxy.sendNotification(connectionId: cid, characteristicUuid: chr, value: value)
        }
    }

    // MARK: - Helpers

    private func send(_ event: BridgeEvent) {
        connection.send(event)
        log("→ \(event)")
    }

    private func log(_ message: String) {
        onLog?(message)
    }
}
