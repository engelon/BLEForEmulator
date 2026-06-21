import CoreBluetooth
import Foundation

// MARK: - BLECentralProxy
// Handles scanning, connecting, and GATT operations on behalf of the emulator.

final class BLECentralProxy: NSObject {

    var onEvent: ((BridgeEvent) -> Void)?

    private var central:     CBCentralManager!
    // scan deferred until BT powers on
    private var pendingScanUuids: [String]? = nil
    // address (CBPeripheral UUID string) → peripheral (retained during scan so we can connect)
    private var discovered:  [String: CBPeripheral] = [:]
    // connectionId → peripheral
    private var connected:   [String: CBPeripheral] = [:]
    // peripheral UUID → connectionId
    private var connectionIds: [String: String] = [:]
    // connectionId → pending request id
    private var pendingIds:  [String: String]   = [:]

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Public commands

    func startScan(serviceUuids: [String]) {
        guard central.state == .poweredOn else {
            pendingScanUuids = serviceUuids   // retry when BT powers on
            return
        }
        executeScan(serviceUuids: serviceUuids)
    }

    private func executeScan(serviceUuids: [String]) {
        let cbuuids = serviceUuids.isEmpty ? nil : serviceUuids.map { CBUUID(string: $0) }
        central.scanForPeripherals(withServices: cbuuids, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        // TODO: expose allowDuplicates as a command option for RSSI-based proximity use cases
    }

    func stopScan() {
        central.stopScan()
    }

    func connect(address: String, id: String?) {
        guard let peripheral = discovered[address] else {
            onEvent?(.connectionFailed(address: address, error: "Peripheral not found — scan first", id: id))
            return
        }
        if let id { pendingIds[address] = id }
        central.connect(peripheral, options: nil)
    }

    func discoverServices(connectionId: String) {
        guard let peripheral = connected[connectionId] else { return }
        peripheral.discoverServices(nil)
        // TODO: accept optional serviceUuids filter to speed up discovery
    }

    func readCharacteristic(connectionId: String, serviceUuid: String, characteristicUuid: String, id: String?) {
        guard let peripheral  = connected[connectionId],
              let char        = findCharacteristic(peripheral, serviceUuid: serviceUuid, uuid: characteristicUuid)
        else { return }
        if let id { pendingIds[connectionId + characteristicUuid] = id }
        peripheral.readValue(for: char)
    }

    func writeCharacteristic(connectionId: String, serviceUuid: String, characteristicUuid: String, value: Data, withResponse: Bool, id: String?) {
        guard let peripheral = connected[connectionId],
              let char       = findCharacteristic(peripheral, serviceUuid: serviceUuid, uuid: characteristicUuid)
        else { return }
        if withResponse, let id { pendingIds[connectionId + characteristicUuid + "write"] = id }
        let type: CBCharacteristicWriteType = withResponse ? .withResponse : .withoutResponse
        peripheral.writeValue(value, for: char, type: type)
    }

    func setNotify(connectionId: String, serviceUuid: String, characteristicUuid: String, enable: Bool) {
        guard let peripheral = connected[connectionId],
              let char       = findCharacteristic(peripheral, serviceUuid: serviceUuid, uuid: characteristicUuid)
        else { return }
        peripheral.setNotifyValue(enable, for: char)
    }

    func disconnect(connectionId: String) {
        guard let peripheral = connected[connectionId] else { return }
        central.cancelPeripheralConnection(peripheral)
    }

    // MARK: - Private helpers

    private func findCharacteristic(_ peripheral: CBPeripheral, serviceUuid: String, uuid: String) -> CBCharacteristic? {
        peripheral.services?
            .first  { $0.uuid == CBUUID(string: serviceUuid) }?
            .characteristics?
            .first  { $0.uuid == CBUUID(string: uuid) }
    }

    private func properties(of char: CBCharacteristic) -> [String] {
        var props: [String] = []
        if char.properties.contains(.read)                 { props.append("read") }
        if char.properties.contains(.write)                { props.append("write") }
        if char.properties.contains(.writeWithoutResponse) { props.append("writeWithoutResponse") }
        if char.properties.contains(.notify)               { props.append("notify") }
        if char.properties.contains(.indicate)             { props.append("indicate") }
        return props
    }
}

// MARK: - CBCentralManagerDelegate

extension BLECentralProxy: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state: String
        switch central.state {
        case .poweredOn:
            state = "poweredOn"
            if let uuids = pendingScanUuids {
                pendingScanUuids = nil
                executeScan(serviceUuids: uuids)
            }
        case .poweredOff:   state = "poweredOff"
        case .unauthorized: state = "unauthorized"
        case .unsupported:  state = "unsupported"
        default:            state = "unknown"
        }
        onEvent?(.bluetoothStateChanged(state: state))
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let address   = peripheral.identifier.uuidString
        discovered[address] = peripheral  // retain so we can connect later

        let name      = peripheral.name
        let rssi      = RSSI.intValue
        let uuidObjs  = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let uuids     = uuidObjs.map { $0.uuidString }
        // TODO: include service data from advertisementData[CBAdvertisementDataServiceDataKey]

        onEvent?(.advertisementFound(address: address, localName: name, rssi: rssi, serviceUuids: uuids))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        let address      = peripheral.identifier.uuidString
        let connectionId = UUID().uuidString
        connected[connectionId]          = peripheral
        connectionIds[address]           = connectionId
        let id = pendingIds.removeValue(forKey: address)
        onEvent?(.connected(connectionId: connectionId, address: address, id: id))
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let address = peripheral.identifier.uuidString
        let id      = pendingIds.removeValue(forKey: address)
        onEvent?(.connectionFailed(address: address, error: error?.localizedDescription ?? "Unknown", id: id))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let address = peripheral.identifier.uuidString
        guard let connectionId = connectionIds.removeValue(forKey: address) else { return }
        connected.removeValue(forKey: connectionId)
        // TODO: auto-reconnect policy for unexpected disconnects
        onEvent?(.disconnected(connectionId: connectionId, error: error?.localizedDescription))
    }
}

// MARK: - CBPeripheralDelegate

extension BLECentralProxy: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        // Always discover characteristics next; emit servicesDiscovered only after all chars are fetched.
        guard let services = peripheral.services, !services.isEmpty else { return }
        services.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let address = peripheral.identifier.uuidString
        guard let connectionId = connectionIds[address] else { return }

        // Check if all services now have characteristics
        let allDiscovered = peripheral.services?.allSatisfy { $0.characteristics != nil } ?? false
        guard allDiscovered else { return }

        let services: [BLEService] = peripheral.services?.map { svc in
            BLEService(
                uuid: svc.uuid.uuidString,
                characteristics: svc.characteristics?.map { char in
                    BLECharacteristic(uuid: char.uuid.uuidString, properties: properties(of: char))
                } ?? []
            )
        } ?? []

        onEvent?(.servicesDiscovered(connectionId: connectionId, services: services))
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let address = peripheral.identifier.uuidString
        guard let connectionId = connectionIds[address],
              let value        = characteristic.value else { return }
        let charUuid           = characteristic.uuid.uuidString

        if characteristic.isNotifying {
            onEvent?(.characteristicChanged(connectionId: connectionId, characteristicUuid: charUuid, value: value))
        } else {
            let id = pendingIds.removeValue(forKey: connectionId + charUuid)
            onEvent?(.characteristicRead(connectionId: connectionId, characteristicUuid: charUuid, value: value, id: id))
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let address = peripheral.identifier.uuidString
        guard let connectionId = connectionIds[address] else { return }
        let charUuid           = characteristic.uuid.uuidString
        let id = pendingIds.removeValue(forKey: connectionId + charUuid + "write")
        // TODO: surface write errors back to emulator
        onEvent?(.writeAcknowledged(connectionId: connectionId, characteristicUuid: charUuid, id: id))
    }
}
