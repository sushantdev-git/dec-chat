package com.bitchat.mesh.dec_chat.ble

import android.bluetooth.BluetoothAdapter
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.os.ParcelUuid
import android.util.Log

interface BleScanListener {
    fun onDeviceDiscovered(scanResult: ScanResult)
}

class BleScannerManager(
    private val bluetoothAdapter: BluetoothAdapter?,
    private val listener: BleScanListener
) {
    private var scanner: BluetoothLeScanner? = null
    private var isScanning = false

    private val callback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult?) {
            if (result != null) {
                val record = result.scanRecord
                val matchesUuid = record?.serviceUuids?.any { it.uuid == BleConstants.SERVICE_UUID } == true
                val matchesName = record?.deviceName?.contains("Grid", ignoreCase = true) == true ||
                    record?.deviceName?.contains("DecChat", ignoreCase = true) == true
                if (matchesUuid || matchesName) {
                    listener.onDeviceDiscovered(result)
                }
            }
        }

        override fun onScanFailed(errorCode: Int) {
            isScanning = false
            Log.e("BleScanner", "Scan failed with error code: $errorCode")
        }
    }

    fun startScanning() {
        if (isScanning) return
        scanner = bluetoothAdapter?.bluetoothLeScanner
        val leScanner = scanner ?: return

        val filterByUuid = ScanFilter.Builder()
            .setServiceUuid(ParcelUuid(BleConstants.SERVICE_UUID))
            .build()
        val filterByNameGrid = ScanFilter.Builder()
            .setDeviceName("Grid")
            .build()
        val filterByNameLegacy = ScanFilter.Builder()
            .setDeviceName("DecChat")
            .build()

        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .setReportDelay(0)
            .build()

        try {
            leScanner.startScan(listOf(filterByUuid, filterByNameGrid, filterByNameLegacy), settings, callback)
            isScanning = true
        } catch (e: SecurityException) {
            Log.e("BleScanner", "Permission error starting scan", e)
        }
    }

    fun stopScanning() {
        if (!isScanning) return
        try {
            scanner?.stopScan(callback)
        } catch (e: SecurityException) {
            Log.e("BleScanner", "Permission error stopping scan", e)
        } finally {
            isScanning = false
        }
    }
}
