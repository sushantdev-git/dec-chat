package com.bitchat.mesh.dec_chat

import com.bitchat.mesh.dec_chat.ble.BlePlatformChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var bleChannel: BlePlatformChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bleChannel = BlePlatformChannel(context, flutterEngine.dartExecutor.binaryMessenger)
    }
}
