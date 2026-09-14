package com.bitchat.mesh.dec_chat.ble

import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.util.Log
import java.util.UUID

interface BleGattClientListener {
    fun onPacketReceived(device: BluetoothDevice, data: ByteArray)
    fun onPeerConnected(device: BluetoothDevice)
    fun onPeerDisconnected(device: BluetoothDevice)
}

class BleGattClientManager(
    private val context: Context,
    private val listener: BleGattClientListener
) {
    private val connectedGatts = mutableMapOf<String, BluetoothGatt>()
    private val peerCharacteristics = mutableMapOf<String, BluetoothGattCharacteristic>()

    private val cccdUuid = UUID.fromString("00002902-0000-1000-8000-00805F9B34FB")

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            val address = gatt.device.address
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                connectedGatts[address] = gatt
                try {
                    // Request MTU 512 for large packet transfers
                    gatt.requestMtu(BleConstants.TARGET_MTU)
                } catch (e: SecurityException) {
                    Log.e("BleGattClient", "Permission error requesting MTU", e)
                }
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                connectedGatts.remove(address)
                peerCharacteristics.remove(address)
                try {
                    gatt.close()
                } catch (e: SecurityException) {
                    Log.e("BleGattClient", "Permission error closing GATT", e)
                }
                listener.onPeerDisconnected(gatt.device)
            }
        }

        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            try {
                gatt.discoverServices()
            } catch (e: SecurityException) {
                Log.e("BleGattClient", "Permission error discovering services", e)
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            val address = gatt.device.address
            val service = gatt.getService(BleConstants.SERVICE_UUID)
            val characteristic = service?.getCharacteristic(BleConstants.PACKET_CHARACTERISTIC_UUID)

            if (characteristic != null) {
                peerCharacteristics[address] = characteristic
                try {
                    gatt.setCharacteristicNotification(characteristic, true)
                    val descriptor = characteristic.getDescriptor(cccdUuid)
                    if (descriptor != null) {
                        descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                        gatt.writeDescriptor(descriptor)
                    }
                } catch (e: SecurityException) {
                    Log.e("BleGattClient", "Permission error configuring notification", e)
                }
                listener.onPeerConnected(gatt.device)
            }
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray
        ) {
            listener.onPacketReceived(gatt.device, value)
        }

        @Deprecated("Deprecated for API < 33")
        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic
        ) {
            val value = characteristic.value
            if (value != null) {
                listener.onPacketReceived(gatt.device, value)
            }
        }
    }

    fun connectDevice(device: BluetoothDevice) {
        val address = device.address
        if (connectedGatts.containsKey(address)) return
        try {
            device.connectGatt(context, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
        } catch (e: SecurityException) {
            Log.e("BleGattClient", "Permission error connecting to device", e)
        }
    }

    fun disconnectAll() {
        for (gatt in connectedGatts.values) {
            try {
                gatt.disconnect()
                gatt.close()
            } catch (e: SecurityException) {
                Log.e("BleGattClient", "Permission error disconnecting", e)
            }
        }
        connectedGatts.clear()
        peerCharacteristics.clear()
    }

    fun broadcastPacket(data: ByteArray) {
        for ((address, gatt) in connectedGatts) {
            val characteristic = peerCharacteristics[address] ?: continue
            writePacket(gatt, characteristic, data)
        }
    }

    fun sendDirected(targetAddress: String, data: ByteArray): Boolean {
        val gatt = connectedGatts[targetAddress] ?: return false
        val characteristic = peerCharacteristics[targetAddress] ?: return false
        writePacket(gatt, characteristic, data)
        return true
    }

    private fun writePacket(
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
        data: ByteArray
    ) {
        characteristic.value = data
        val writeType = if ((characteristic.properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE) != 0) {
            BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
        } else {
            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        }
        characteristic.writeType = writeType

        try {
            gatt.writeCharacteristic(characteristic)
        } catch (e: SecurityException) {
            Log.e("BleGattClient", "Permission error writing characteristic", e)
        }
    }
}
