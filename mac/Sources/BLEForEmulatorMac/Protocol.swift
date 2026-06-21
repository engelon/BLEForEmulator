import Foundation

// MARK: - Supporting types

struct AdvertiseCharacteristic {
    let serviceUuid:        String
    let characteristicUuid: String
    let properties:         [String]
    let permissions:        [String]
}

struct BLECharacteristic {
    let uuid:       String
    let properties: [String]
}

struct BLEService {
    let uuid:            String
    let characteristics: [BLECharacteristic]
}

// MARK: - Commands (emulator → Mac)

enum BridgeCommand {
    case startScan(serviceUuids: [String])
    case stopScan
    case connect(address: String, id: String?)
    case discoverServices(connectionId: String)
    case readCharacteristic(connectionId: String, serviceUuid: String, characteristicUuid: String, id: String?)
    case writeCharacteristic(connectionId: String, serviceUuid: String, characteristicUuid: String, value: Data, withResponse: Bool, id: String?)
    case setNotify(connectionId: String, serviceUuid: String, characteristicUuid: String, enable: Bool)
    case advertise(serviceUuids: [String], localName: String?, characteristics: [AdvertiseCharacteristic])
    case stopAdvertise
    case sendNotification(connectionId: String, serviceUuid: String, characteristicUuid: String, value: Data)
    case disconnect(connectionId: String)

    static func parse(_ json: [String: Any]) -> BridgeCommand? {
        guard let name = json["command"] as? String else { return nil }
        let id = json["id"] as? String

        switch name {
        case "startScan":
            return .startScan(serviceUuids: json["serviceUuids"] as? [String] ?? [])

        case "stopScan":
            return .stopScan

        case "connect":
            guard let address = json["address"] as? String else { return nil }
            return .connect(address: address, id: id)

        case "discoverServices":
            guard let cid = json["connectionId"] as? String else { return nil }
            return .discoverServices(connectionId: cid)

        case "readCharacteristic":
            guard let cid  = json["connectionId"] as? String,
                  let svc  = json["serviceUuid"] as? String,
                  let chr  = json["characteristicUuid"] as? String else { return nil }
            return .readCharacteristic(connectionId: cid, serviceUuid: svc, characteristicUuid: chr, id: id)

        case "writeCharacteristic":
            guard let cid     = json["connectionId"] as? String,
                  let svc     = json["serviceUuid"] as? String,
                  let chr     = json["characteristicUuid"] as? String,
                  let b64     = json["value"] as? String,
                  let value   = Data(base64Encoded: b64) else { return nil }
            let withResponse  = json["withResponse"] as? Bool ?? true
            return .writeCharacteristic(connectionId: cid, serviceUuid: svc, characteristicUuid: chr, value: value, withResponse: withResponse, id: id)

        case "setNotify":
            guard let cid    = json["connectionId"] as? String,
                  let svc    = json["serviceUuid"] as? String,
                  let chr    = json["characteristicUuid"] as? String,
                  let enable = json["enable"] as? Bool else { return nil }
            return .setNotify(connectionId: cid, serviceUuid: svc, characteristicUuid: chr, enable: enable)

        case "advertise":
            let serviceUuids = json["serviceUuids"] as? [String] ?? []
            let localName    = json["localName"] as? String
            let rawChars     = json["characteristics"] as? [[String: Any]] ?? []
            let chars: [AdvertiseCharacteristic] = rawChars.compactMap { c in
                guard let svc = c["serviceUuid"] as? String,
                      let chr = c["characteristicUuid"] as? String else { return nil }
                return AdvertiseCharacteristic(
                    serviceUuid:        svc,
                    characteristicUuid: chr,
                    properties:         c["properties"] as? [String] ?? [],
                    permissions:        c["permissions"] as? [String] ?? []
                )
            }
            return .advertise(serviceUuids: serviceUuids, localName: localName, characteristics: chars)

        case "stopAdvertise":
            return .stopAdvertise

        case "sendNotification":
            guard let cid   = json["connectionId"] as? String,
                  let svc   = json["serviceUuid"] as? String,
                  let chr   = json["characteristicUuid"] as? String,
                  let b64   = json["value"] as? String,
                  let value = Data(base64Encoded: b64) else { return nil }
            return .sendNotification(connectionId: cid, serviceUuid: svc, characteristicUuid: chr, value: value)

        case "disconnect":
            guard let cid = json["connectionId"] as? String else { return nil }
            return .disconnect(connectionId: cid)

        default:
            return nil  // TODO: log unknown commands
        }
    }
}

// MARK: - Events (Mac → emulator)

enum BridgeEvent {
    case bridgeReady(bluetoothState: String)
    case bluetoothStateChanged(state: String)
    case advertisementFound(address: String, localName: String?, rssi: Int, serviceUuids: [String])
    case scanFailed(error: String)
    case connected(connectionId: String, address: String, id: String?)
    case connectionFailed(address: String, error: String, id: String?)
    case servicesDiscovered(connectionId: String, services: [BLEService])
    case characteristicRead(connectionId: String, characteristicUuid: String, value: Data, id: String?)
    case characteristicChanged(connectionId: String, characteristicUuid: String, value: Data)
    case writeAcknowledged(connectionId: String, characteristicUuid: String, id: String?)
    case connectionRequestReceived(connectionId: String)
    case characteristicWriteReceived(connectionId: String, serviceUuid: String, characteristicUuid: String, value: Data)
    case disconnected(connectionId: String, error: String?)

    func toJSON() -> [String: Any] {
        switch self {
        case .bridgeReady(let state):
            return ["event": "bridgeReady", "protocolVersion": 1, "platform": "macOS", "bluetoothState": state]

        case .bluetoothStateChanged(let state):
            return ["event": "bluetoothStateChanged", "bluetoothState": state]

        case .advertisementFound(let address, let name, let rssi, let uuids):
            var d: [String: Any] = ["event": "advertisementFound", "address": address, "rssi": rssi, "serviceUuids": uuids]
            if let name { d["localName"] = name }
            return d

        case .scanFailed(let error):
            return ["event": "scanFailed", "error": error]

        case .connected(let cid, let address, let id):
            var d: [String: Any] = ["event": "connected", "connectionId": cid, "address": address]
            if let id { d["id"] = id }
            return d

        case .connectionFailed(let address, let error, let id):
            var d: [String: Any] = ["event": "connectionFailed", "address": address, "error": error]
            if let id { d["id"] = id }
            return d

        case .servicesDiscovered(let cid, let services):
            let s = services.map { svc -> [String: Any] in
                ["uuid": svc.uuid, "characteristics": svc.characteristics.map { c in
                    ["uuid": c.uuid, "properties": c.properties]
                }]
            }
            return ["event": "servicesDiscovered", "connectionId": cid, "services": s]

        case .characteristicRead(let cid, let chr, let value, let id):
            var d: [String: Any] = ["event": "characteristicRead", "connectionId": cid, "characteristicUuid": chr, "value": value.base64EncodedString()]
            if let id { d["id"] = id }
            return d

        case .characteristicChanged(let cid, let chr, let value):
            return ["event": "characteristicChanged", "connectionId": cid, "characteristicUuid": chr, "value": value.base64EncodedString()]

        case .writeAcknowledged(let cid, let chr, let id):
            var d: [String: Any] = ["event": "writeAcknowledged", "connectionId": cid, "characteristicUuid": chr]
            if let id { d["id"] = id }
            return d

        case .connectionRequestReceived(let cid):
            return ["event": "connectionRequestReceived", "connectionId": cid]

        case .characteristicWriteReceived(let cid, let svc, let chr, let value):
            return ["event": "characteristicWriteReceived", "connectionId": cid,
                    "serviceUuid": svc, "characteristicUuid": chr, "value": value.base64EncodedString()]

        case .disconnected(let cid, let error):
            var d: [String: Any] = ["event": "disconnected", "connectionId": cid]
            if let error { d["error"] = error }
            return d
        }
    }

    func encode() -> Data? {
        guard let data = try? JSONSerialization.data(withJSONObject: toJSON()),
              var line = String(data: data, encoding: .utf8) else { return nil }
        line += "\n"
        return line.data(using: .utf8)
    }
}

// MARK: - Helpers

func parseLine(_ line: String) -> BridgeCommand? {
    guard let data = line.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return BridgeCommand.parse(json)
}
