import CoreBluetooth
import Foundation

// MARK: - BLEPeripheralProxy
// Handles advertising and GATT server operations on behalf of the emulator.

final class BLEPeripheralProxy: NSObject {

    var onEvent: ((BridgeEvent) -> Void)?

    private var manager:        CBPeripheralManager!
    // advertise request deferred until peripheral manager powers on
    private var pendingAdvertise: (serviceUuids: [String], localName: String?, chars: [AdvertiseCharacteristic])? = nil
    // characteristicUuid → CBMutableCharacteristic
    private var characteristics: [String: CBMutableCharacteristic] = [:]
    // connectionId → CBCentral
    private var centrals:       [String: CBCentral] = [:]
    // CBCentral identifier → connectionId
    private var centralIds:     [UUID: String]      = [:]

    override init() {
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: .main)
    }

    // MARK: - Public commands

    func startAdvertising(serviceUuids: [String], localName: String?, advertiseChars: [AdvertiseCharacteristic]) {
        guard manager.state == .poweredOn else {
            pendingAdvertise = (serviceUuids, localName, advertiseChars)
            return
        }
        executeAdvertise(serviceUuids: serviceUuids, localName: localName, advertiseChars: advertiseChars)
    }

    private func executeAdvertise(serviceUuids: [String], localName: String?, advertiseChars: [AdvertiseCharacteristic]) {
        manager.removeAllServices()
        characteristics.removeAll()

        // Group characteristics by service
        var serviceMap: [String: [CBMutableCharacteristic]] = [:]

        for ac in advertiseChars {
            let props = cbProperties(from: ac.properties)
            let perms = cbPermissions(from: ac.permissions)
            let char  = CBMutableCharacteristic(type:        CBUUID(string: ac.characteristicUuid),
                                                properties:  props,
                                                value:       nil,
                                                permissions: perms)
            characteristics[ac.characteristicUuid] = char
            serviceMap[ac.serviceUuid, default: []].append(char)
        }

        for (uuid, chars) in serviceMap {
            let service = CBMutableService(type: CBUUID(string: uuid), primary: true)
            service.characteristics = chars
            manager.add(service)
        }

        var advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: serviceUuids.map { CBUUID(string: $0) }
        ]
        if let localName { advertisementData[CBAdvertisementDataLocalNameKey] = localName }
        // TODO: validate advertisement payload size (31-byte limit for non-connectable packets)

        manager.startAdvertising(advertisementData)
    }

    func stopAdvertising() {
        manager.stopAdvertising()
        manager.removeAllServices()
        characteristics.removeAll()
    }

    func sendNotification(connectionId: String, characteristicUuid: String, value: Data) {
        guard let char    = characteristics[characteristicUuid],
              let central = centrals[connectionId] else { return }
        // TODO: handle updateValue returning false (queue full) and retry via peripheralManagerIsReady
        manager.updateValue(value, for: char, onSubscribedCentrals: [central])
    }

    // MARK: - Private helpers

    private func cbProperties(from props: [String]) -> CBCharacteristicProperties {
        var result: CBCharacteristicProperties = []
        if props.contains("read")                 { result.insert(.read) }
        if props.contains("write")                { result.insert(.write) }
        if props.contains("writeWithoutResponse") { result.insert(.writeWithoutResponse) }
        if props.contains("notify")               { result.insert(.notify) }
        if props.contains("indicate")             { result.insert(.indicate) }
        return result
    }

    private func cbPermissions(from perms: [String]) -> CBAttributePermissions {
        var result: CBAttributePermissions = []
        if perms.contains("readable")  { result.insert(.readable) }
        if perms.contains("writeable") { result.insert(.writeable) }
        return result
    }
}

// MARK: - CBPeripheralManagerDelegate

extension BLEPeripheralProxy: CBPeripheralManagerDelegate {

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn, let p = pendingAdvertise {
            pendingAdvertise = nil
            executeAdvertise(serviceUuids: p.serviceUuids, localName: p.localName, advertiseChars: p.chars)
        }
        // Bluetooth state changes are also reported via BLECentralProxy's CBCentralManager
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            peripheral.respond(to: request, withResult: .success)

            let centralId    = request.central.identifier
            let connectionId: String
            if let existing = centralIds[centralId] {
                connectionId = existing
            } else {
                connectionId = UUID().uuidString
                centrals[connectionId]   = request.central
                centralIds[centralId]    = connectionId
                onEvent?(.connectionRequestReceived(connectionId: connectionId))
            }

            guard let value = request.value else { continue }
            onEvent?(.characteristicWriteReceived(
                connectionId:       connectionId,
                serviceUuid:        request.characteristic.service?.uuid.uuidString ?? "",
                characteristicUuid: request.characteristic.uuid.uuidString,
                value:              value
            ))
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           central: CBCentral,
                           didSubscribeTo characteristic: CBCharacteristic) {
        let centralId = central.identifier
        if centralIds[centralId] == nil {
            let connectionId = UUID().uuidString
            centrals[connectionId] = central
            centralIds[centralId]  = connectionId
            onEvent?(.connectionRequestReceived(connectionId: connectionId))
        }
        // TODO: notify emulator that this specific central subscribed to this characteristic
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           central: CBCentral,
                           didUnsubscribeFrom characteristic: CBCharacteristic) {
        // TODO: notify emulator of unsubscription
    }
}
