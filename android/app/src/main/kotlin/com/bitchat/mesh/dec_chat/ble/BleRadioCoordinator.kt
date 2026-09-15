package com.bitchat.mesh.dec_chat.ble

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanResult
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log

interface BleRadioCoordinatorListener {
    fun onPacketReceived(data: ByteArray, peerId: String, rssi: Int?)
    fun onPeerConnected(peerId: String)
    fun onPeerDisconnected(peerId: String)
    fun onAdapterStateChanged(isPoweredOn: Boolean)
}

enum class PowerMode {
    ACTIVE,
    BALANCED,
    BACKGROUND;

    companion object {
        fun fromString(value: String): PowerMode = when (value.lowercase()) {
            "balanced" -> BALANCED
            "background" -> BACKGROUND
            else -> ACTIVE
        }
    }
}

class BleRadioCoordinator(
    context: Context,
    private val listener: BleRadioCoordinatorListener
) : BleGattServerListener, BleGattClientListener, BleScanListener {

    private val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
    private val bluetoothAdapter: BluetoothAdapter? = bluetoothManager?.adapter

    private val advertiserManager = BleAdvertiserManager(bluetoothAdapter)
    private val serverManager = BleGattServerManager(context, bluetoothManager, this)
    private val scannerManager = BleScannerManager(bluetoothAdapter, this)
    private val clientManager = BleGattClientManager(context, this)

    private val handler = Handler(Looper.getMainLooper())
    private var powerMode = PowerMode.ACTIVE
    private var dutyCycleRunnable: Runnable? = null

    private val connectedPeers = mutableSetOf<String>()

    fun start(mode: PowerMode = PowerMode.ACTIVE) {
        this.powerMode = mode
        serverManager.startServer()
        advertiserManager.startAdvertising()
        applyDutyCycle()
        listener.onAdapterStateChanged(bluetoothAdapter?.isEnabled == true)
    }

    fun restartScan() {
        this.powerMode = PowerMode.ACTIVE
        dutyCycleRunnable?.let { handler.removeCallbacks(it) }
        dutyCycleRunnable = null

        serverManager.startServer()
        advertiserManager.startAdvertising()

        try {
            val connectedGattDevices = bluetoothManager?.getConnectedDevices(BluetoothProfile.GATT)
            connectedGattDevices?.forEach { device ->
                clientManager.connectDevice(device)
            }
        } catch (e: SecurityException) {
            Log.e("BleRadioCoordinator", "Permission error checking connected GATT devices", e)
        }

        scannerManager.startScanning()
        listener.onAdapterStateChanged(bluetoothAdapter?.isEnabled == true)
    }

    fun stop() {
        dutyCycleRunnable?.let { handler.removeCallbacks(it) }
        dutyCycleRunnable = null

        scannerManager.stopScanning()
        advertiserManager.stopAdvertising()
        clientManager.disconnectAll()
        serverManager.stopServer()
        connectedPeers.clear()
    }

    fun setPowerMode(mode: PowerMode) {
        this.powerMode = mode
        applyDutyCycle()
    }

    fun sendBroadcast(data: ByteArray) {
        serverManager.broadcastPacket(data)
        clientManager.broadcastPacket(data)
    }

    fun sendDirected(peerId: String, data: ByteArray) {
        if (!clientManager.sendDirected(peerId, data)) {
            serverManager.sendDirected(peerId, data)
        }
    }

    fun getConnectedPeers(): List<String> = connectedPeers.toList()

    private fun applyDutyCycle() {
        dutyCycleRunnable?.let { handler.removeCallbacks(it) }
        dutyCycleRunnable = null

        when (powerMode) {
            PowerMode.ACTIVE -> {
                scannerManager.startScanning()
                advertiserManager.startAdvertising()
            }
            PowerMode.BALANCED -> {
                scheduleDutyCycle(15000L, 15000L)
            }
            PowerMode.BACKGROUND -> {
                scheduleDutyCycle(5000L, 55000L)
            }
        }
    }

    private fun scheduleDutyCycle(activeDurationMs: Long, idleDurationMs: Long) {
        scannerManager.startScanning()

        val idleRunnable = Runnable {
            scannerManager.stopScanning()
            val resumeRunnable = Runnable {
                applyDutyCycle()
            }
            dutyCycleRunnable = resumeRunnable
            handler.postDelayed(resumeRunnable, idleDurationMs)
        }
        dutyCycleRunnable = idleRunnable
        handler.postDelayed(idleRunnable, activeDurationMs)
    }

    // BleScanListener
    override fun onDeviceDiscovered(scanResult: ScanResult) {
        clientManager.connectDevice(scanResult.device)
    }

    // BleGattServerListener
    override fun onPacketReceived(device: BluetoothDevice, data: ByteArray) {
        listener.onPacketReceived(data, device.address, null)
    }

    override fun onClientConnected(device: BluetoothDevice) {
        connectedPeers.add(device.address)
        listener.onPeerConnected(device.address)
    }

    override fun onClientDisconnected(device: BluetoothDevice) {
        connectedPeers.remove(device.address)
        listener.onPeerDisconnected(device.address)
    }

    // BleGattClientListener
    override fun onPeerConnected(device: BluetoothDevice) {
        connectedPeers.add(device.address)
        listener.onPeerConnected(device.address)
    }

    override fun onPeerDisconnected(device: BluetoothDevice) {
        connectedPeers.remove(device.address)
        listener.onPeerDisconnected(device.address)
    }
}
