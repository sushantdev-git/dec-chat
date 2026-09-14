package com.bitchat.mesh.dec_chat.ble

import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.util.Log

interface BleGattServerListener {
    fun onPacketReceived(device: BluetoothDevice, data: ByteArray)
    fun onClientConnected(device: BluetoothDevice)
    fun onClientDisconnected(device: BluetoothDevice)
}

class BleGattServerManager(
    private val context: Context,
    private val bluetoothManager: BluetoothManager?,
    private val listener: BleGattServerListener
) {
    private var gattServer: BluetoothGattServer? = null
    private var packetCharacteristic: BluetoothGattCharacteristic? = null
    private val connectedDevices = mutableSetOf<BluetoothDevice>()

    private val callback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                connectedDevices.add(device)
                listener.onClientConnected(device)
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                connectedDevices.remove(device)
                listener.onClientDisconnected(device)
            }
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?
        ) {
            if (responseNeeded) {
                try {
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
                } catch (e: SecurityException) {
                    Log.e("BleGattServer", "Permission error sending response", e)
                }
            }

            if (value != null && value.isNotEmpty()) {
                listener.onPacketReceived(device, value)
            }
        }
    }

    fun startServer() {
        if (gattServer != null) return
        try {
            gattServer = bluetoothManager?.openGattServer(context, callback)
            setupService()
        } catch (e: SecurityException) {
            Log.e("BleGattServer", "Permission error opening GATT server", e)
        }
    }

    fun stopServer() {
        try {
            gattServer?.clearServices()
            gattServer?.close()
        } catch (e: SecurityException) {
            Log.e("BleGattServer", "Permission error closing GATT server", e)
        } finally {
            gattServer = null
            connectedDevices.clear()
        }
    }

    private fun setupService() {
        val characteristic = BluetoothGattCharacteristic(
            BleConstants.PACKET_CHARACTERISTIC_UUID,
            BluetoothGattCharacteristic.PROPERTY_WRITE or
                    BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE or
                    BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_WRITE
        )
        this.packetCharacteristic = characteristic

        val service = BluetoothGattService(
            BleConstants.SERVICE_UUID,
            BluetoothGattService.SERVICE_TYPE_PRIMARY
        )
        service.addCharacteristic(characteristic)

        try {
            gattServer?.addService(service)
        } catch (e: SecurityException) {
            Log.e("BleGattServer", "Permission error adding GATT service", e)
        }
    }

    fun broadcastPacket(data: ByteArray) {
        val characteristic = packetCharacteristic ?: return
        characteristic.value = data
        for (device in connectedDevices) {
            try {
                gattServer?.notifyCharacteristicChanged(device, characteristic, false)
            } catch (e: SecurityException) {
                Log.e("BleGattServer", "Permission error notifying device", e)
            }
        }
    }

    fun sendDirected(deviceAddress: String, data: ByteArray) {
        val characteristic = packetCharacteristic ?: return
        characteristic.value = data
        val target = connectedDevices.find { it.address.equals(deviceAddress, ignoreCase = true) } ?: return
        try {
            gattServer?.notifyCharacteristicChanged(target, characteristic, false)
        } catch (e: SecurityException) {
            Log.e("BleGattServer", "Permission error notifying directed device", e)
        }
    }
}
