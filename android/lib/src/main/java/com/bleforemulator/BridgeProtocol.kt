package com.bleforemulator

import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject

// MARK: - Commands (Android → Mac)

sealed class BridgeCommand {
    data class StartScan(val serviceUuids: List<String> = emptyList()) : BridgeCommand()
    object StopScan : BridgeCommand()
    data class Connect(val address: String, val id: String? = null) : BridgeCommand()
    data class DiscoverServices(val connectionId: String) : BridgeCommand()
    data class ReadCharacteristic(val connectionId: String, val serviceUuid: String, val characteristicUuid: String, val id: String? = null) : BridgeCommand()
    data class WriteCharacteristic(val connectionId: String, val serviceUuid: String, val characteristicUuid: String, val value: ByteArray, val withResponse: Boolean = true, val id: String? = null) : BridgeCommand()
    data class SetNotify(val connectionId: String, val serviceUuid: String, val characteristicUuid: String, val enable: Boolean) : BridgeCommand()
    data class Advertise(val serviceUuids: List<String>, val localName: String? = null, val characteristics: List<AdvertiseCharacteristic> = emptyList()) : BridgeCommand()
    object StopAdvertise : BridgeCommand()
    data class SendNotification(val connectionId: String, val serviceUuid: String, val characteristicUuid: String, val value: ByteArray) : BridgeCommand()
    data class Disconnect(val connectionId: String) : BridgeCommand()

    fun toJson(): String {
        val obj = JSONObject()
        when (this) {
            is StartScan -> {
                obj.put("command", "startScan")
                obj.put("serviceUuids", JSONArray(serviceUuids))
            }
            is StopScan -> obj.put("command", "stopScan")
            is Connect -> {
                obj.put("command", "connect")
                obj.put("address", address)
                id?.let { obj.put("id", it) }
            }
            is DiscoverServices -> {
                obj.put("command", "discoverServices")
                obj.put("connectionId", connectionId)
            }
            is ReadCharacteristic -> {
                obj.put("command", "readCharacteristic")
                obj.put("connectionId", connectionId)
                obj.put("serviceUuid", serviceUuid)
                obj.put("characteristicUuid", characteristicUuid)
                id?.let { obj.put("id", it) }
            }
            is WriteCharacteristic -> {
                obj.put("command", "writeCharacteristic")
                obj.put("connectionId", connectionId)
                obj.put("serviceUuid", serviceUuid)
                obj.put("characteristicUuid", characteristicUuid)
                obj.put("value", Base64.encodeToString(value, Base64.NO_WRAP))
                obj.put("withResponse", withResponse)
                id?.let { obj.put("id", it) }
            }
            is SetNotify -> {
                obj.put("command", "setNotify")
                obj.put("connectionId", connectionId)
                obj.put("serviceUuid", serviceUuid)
                obj.put("characteristicUuid", characteristicUuid)
                obj.put("enable", enable)
            }
            is Advertise -> {
                obj.put("command", "advertise")
                obj.put("serviceUuids", JSONArray(serviceUuids))
                localName?.let { obj.put("localName", it) }
                val chars = JSONArray()
                characteristics.forEach { ac ->
                    chars.put(JSONObject().apply {
                        put("serviceUuid", ac.serviceUuid)
                        put("characteristicUuid", ac.characteristicUuid)
                        put("properties", JSONArray(ac.properties))
                        put("permissions", JSONArray(ac.permissions))
                    })
                }
                obj.put("characteristics", chars)
            }
            is StopAdvertise -> obj.put("command", "stopAdvertise")
            is SendNotification -> {
                obj.put("command", "sendNotification")
                obj.put("connectionId", connectionId)
                obj.put("serviceUuid", serviceUuid)
                obj.put("characteristicUuid", characteristicUuid)
                obj.put("value", Base64.encodeToString(value, Base64.NO_WRAP))
            }
            is Disconnect -> {
                obj.put("command", "disconnect")
                obj.put("connectionId", connectionId)
            }
        }
        return obj.toString()
    }
}

data class AdvertiseCharacteristic(
    val serviceUuid: String,
    val characteristicUuid: String,
    val properties: List<String> = listOf("write", "notify"),
    val permissions: List<String> = listOf("readable", "writeable")
)

// MARK: - Events (Mac → Android)

sealed class BridgeEvent {
    data class BridgeReady(val bluetoothState: String) : BridgeEvent()
    data class BluetoothStateChanged(val state: String) : BridgeEvent()
    data class AdvertisementFound(val address: String, val localName: String?, val rssi: Int, val serviceUuids: List<String>) : BridgeEvent()
    data class ScanFailed(val error: String) : BridgeEvent()
    data class Connected(val connectionId: String, val address: String, val id: String?) : BridgeEvent()
    data class ConnectionFailed(val address: String, val error: String, val id: String?) : BridgeEvent()
    data class ServicesDiscovered(val connectionId: String, val services: List<BLEService>) : BridgeEvent()
    data class CharacteristicRead(val connectionId: String, val characteristicUuid: String, val value: ByteArray, val id: String?) : BridgeEvent()
    data class CharacteristicChanged(val connectionId: String, val characteristicUuid: String, val value: ByteArray) : BridgeEvent()
    data class WriteAcknowledged(val connectionId: String, val characteristicUuid: String, val id: String?) : BridgeEvent()
    data class ConnectionRequestReceived(val connectionId: String) : BridgeEvent()
    data class CharacteristicWriteReceived(val connectionId: String, val serviceUuid: String, val characteristicUuid: String, val value: ByteArray) : BridgeEvent()
    data class Disconnected(val connectionId: String, val error: String?) : BridgeEvent()
    data class ParseError(val line: String) : BridgeEvent()

    companion object {
        fun parse(line: String): BridgeEvent? = runCatching {
            val obj = JSONObject(line)
            when (val name = obj.getString("event")) {
                "bridgeReady" -> BridgeReady(obj.optString("bluetoothState", "unknown"))
                "bluetoothStateChanged" -> BluetoothStateChanged(obj.getString("bluetoothState"))
                "advertisementFound" -> AdvertisementFound(
                    address     = obj.getString("address"),
                    localName   = obj.optString("localName").takeIf { it.isNotEmpty() },
                    rssi        = obj.optInt("rssi", -100),
                    serviceUuids = obj.optJSONArray("serviceUuids")?.let { arr ->
                        (0 until arr.length()).map { arr.getString(it) }
                    } ?: emptyList()
                )
                "scanFailed" -> ScanFailed(obj.getString("error"))
                "connected" -> Connected(
                    connectionId = obj.getString("connectionId"),
                    address      = obj.getString("address"),
                    id           = obj.optString("id").takeIf { it.isNotEmpty() }
                )
                "connectionFailed" -> ConnectionFailed(
                    address = obj.getString("address"),
                    error   = obj.getString("error"),
                    id      = obj.optString("id").takeIf { it.isNotEmpty() }
                )
                "servicesDiscovered" -> ServicesDiscovered(
                    connectionId = obj.getString("connectionId"),
                    services     = obj.optJSONArray("services")?.let { arr ->
                        (0 until arr.length()).map { i ->
                            val svc = arr.getJSONObject(i)
                            val chars = svc.optJSONArray("characteristics")?.let { ca ->
                                (0 until ca.length()).map { j ->
                                    val c = ca.getJSONObject(j)
                                    BLECharacteristic(
                                        uuid       = c.getString("uuid"),
                                        properties = c.optJSONArray("properties")?.let { pa ->
                                            (0 until pa.length()).map { pa.getString(it) }
                                        } ?: emptyList()
                                    )
                                }
                            } ?: emptyList()
                            BLEService(uuid = svc.getString("uuid"), characteristics = chars)
                        }
                    } ?: emptyList()
                )
                "characteristicRead" -> CharacteristicRead(
                    connectionId       = obj.getString("connectionId"),
                    characteristicUuid = obj.getString("characteristicUuid"),
                    value              = Base64.decode(obj.getString("value"), Base64.DEFAULT),
                    id                 = obj.optString("id").takeIf { it.isNotEmpty() }
                )
                "characteristicChanged" -> CharacteristicChanged(
                    connectionId       = obj.getString("connectionId"),
                    characteristicUuid = obj.getString("characteristicUuid"),
                    value              = Base64.decode(obj.getString("value"), Base64.DEFAULT)
                )
                "writeAcknowledged" -> WriteAcknowledged(
                    connectionId       = obj.getString("connectionId"),
                    characteristicUuid = obj.getString("characteristicUuid"),
                    id                 = obj.optString("id").takeIf { it.isNotEmpty() }
                )
                "connectionRequestReceived" -> ConnectionRequestReceived(obj.getString("connectionId"))
                "characteristicWriteReceived" -> CharacteristicWriteReceived(
                    connectionId       = obj.getString("connectionId"),
                    serviceUuid        = obj.getString("serviceUuid"),
                    characteristicUuid = obj.getString("characteristicUuid"),
                    value              = Base64.decode(obj.getString("value"), Base64.DEFAULT)
                )
                "disconnected" -> Disconnected(
                    connectionId = obj.getString("connectionId"),
                    error        = obj.optString("error").takeIf { it.isNotEmpty() }
                )
                else -> null  // TODO: log unknown event name
            }
        }.getOrNull()
    }
}

data class BLECharacteristic(val uuid: String, val properties: List<String>)
data class BLEService(val uuid: String, val characteristics: List<BLECharacteristic>)
