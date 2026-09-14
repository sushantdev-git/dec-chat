package com.bitchat.mesh.dec_chat.ble

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class BlePlatformChannel(
    context: Context,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler, BleRadioCoordinatorListener {

    private val coordinator = BleRadioCoordinator(context, this)
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        val methodChannel = MethodChannel(messenger, BleConstants.CONTROL_CHANNEL_NAME)
        methodChannel.setMethodCallHandler(this)

        val eventChannel = EventChannel(messenger, BleConstants.EVENT_CHANNEL_NAME)
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val modeString = call.argument<String>("mode") ?: "active"
                coordinator.start(PowerMode.fromString(modeString))
                result.success(true)
            }
            "stop" -> {
                coordinator.stop()
                result.success(true)
            }
            "sendBroadcast" -> {
                val data = call.argument<ByteArray>("data")
                if (data != null) {
                    coordinator.sendBroadcast(data)
                    result.success(true)
                } else {
                    result.error("INVALID_ARGS", "Missing data parameter", null)
                }
            }
            "sendDirected" -> {
                val peerId = call.argument<String>("peerId")
                val data = call.argument<ByteArray>("data")
                if (peerId != null && data != null) {
                    coordinator.sendDirected(peerId, data)
                    result.success(true)
                } else {
                    result.error("INVALID_ARGS", "Missing peerId or data parameter", null)
                }
            }
            "setPowerMode" -> {
                val modeString = call.argument<String>("mode") ?: "active"
                coordinator.setPowerMode(PowerMode.fromString(modeString))
                result.success(true)
            }
            "getConnectedPeers" -> {
                result.success(coordinator.getConnectedPeers())
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        this.eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        this.eventSink = null
    }

    // BleRadioCoordinatorListener
    override fun onPacketReceived(data: ByteArray, peerId: String, rssi: Int?) {
        mainHandler.post {
            val map = mutableMapOf<String, Any>(
                "type" to "packetReceived",
                "data" to data,
                "peerId" to peerId
            )
            rssi?.let { map["rssi"] = it }
            eventSink?.success(map)
        }
    }

    override fun onPeerConnected(peerId: String) {
        mainHandler.post {
            eventSink?.success(
                mapOf(
                    "type" to "peerConnected",
                    "peerId" to peerId
                )
            )
        }
    }

    override fun onPeerDisconnected(peerId: String) {
        mainHandler.post {
            eventSink?.success(
                mapOf(
                    "type" to "peerDisconnected",
                    "peerId" to peerId
                )
            )
        }
    }

    override fun onAdapterStateChanged(isPoweredOn: Boolean) {
        mainHandler.post {
            eventSink?.success(
                mapOf(
                    "type" to "adapterStateChanged",
                    "state" to if (isPoweredOn) "poweredOn" else "poweredOff"
                )
            )
        }
    }
}
