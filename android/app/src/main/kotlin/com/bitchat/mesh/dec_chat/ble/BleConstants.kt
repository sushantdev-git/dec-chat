package com.bitchat.mesh.dec_chat.ble

import java.util.UUID

object BleConstants {
    val SERVICE_UUID: UUID = UUID.fromString("0000FDC7-0000-1000-8000-00805F9B34FB")
    val PACKET_CHARACTERISTIC_UUID: UUID = UUID.fromString("00002A06-0000-1000-8000-00805F9B34FB")

    const val CONTROL_CHANNEL_NAME = "com.bitchat.mesh/ble_control"
    const val EVENT_CHANNEL_NAME = "com.bitchat.mesh/ble_events"

    const val TARGET_MTU = 512
}
