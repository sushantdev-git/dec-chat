package com.bitchat.mesh.dec_chat.ble

import android.bluetooth.BluetoothAdapter
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.os.ParcelUuid
import android.util.Log

class BleAdvertiserManager(private val bluetoothAdapter: BluetoothAdapter?) {
    private var advertiser: BluetoothLeAdvertiser? = null
    private var isAdvertising = false

    private val callback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            isAdvertising = true
            Log.d("BleAdvertiser", "Advertising started successfully")
        }

        override fun onStartFailure(errorCode: Int) {
            isAdvertising = false
            Log.e("BleAdvertiser", "Advertising failed with error code: $errorCode")
        }
    }

    fun startAdvertising() {
        if (isAdvertising) return
        advertiser = bluetoothAdapter?.bluetoothLeAdvertiser
        val leAdvertiser = advertiser ?: return

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(true)
            .build()

        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .addServiceUuid(ParcelUuid(BleConstants.SERVICE_UUID))
            .build()

        try {
            leAdvertiser.startAdvertising(settings, data, callback)
        } catch (e: SecurityException) {
            Log.e("BleAdvertiser", "Permission denied for advertising", e)
        }
    }

    fun stopAdvertising() {
        if (!isAdvertising) return
        try {
            advertiser?.stopAdvertising(callback)
        } catch (e: SecurityException) {
            Log.e("BleAdvertiser", "Permission denied when stopping advertising", e)
        } finally {
            isAdvertising = false
        }
    }
}
