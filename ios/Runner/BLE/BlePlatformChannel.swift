import Foundation
import Flutter

class BlePlatformChannel: NSObject, FlutterStreamHandler, BLERadioCoordinatorDelegate {
    private let radioCoordinator: BLERadioCoordinator
    private var eventSink: FlutterEventSink?
    
    init(messenger: FlutterBinaryMessenger) {
        self.radioCoordinator = BLERadioCoordinator()
        super.init()
        
        self.radioCoordinator.delegate = self
        
        let methodChannel = FlutterMethodChannel(
            name: BLEConstants.controlChannelName,
            binaryMessenger: messenger
        )
        methodChannel.setMethodCallHandler(handleMethodCall)
        
        let eventChannel = FlutterEventChannel(
            name: BLEConstants.eventChannelName,
            binaryMessenger: messenger
        )
        eventChannel.setStreamHandler(self)
    }
    
    private func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "start":
            let args = call.arguments as? [String: Any]
            let modeString = args?["mode"] as? String ?? "active"
            let mode = PowerMode(rawValue: modeString) ?? .active
            radioCoordinator.start(mode: mode)
            result(true)
            
        case "stop":
            radioCoordinator.stop()
            result(true)
            
        case "sendBroadcast":
            guard let args = call.arguments as? [String: Any],
                  let flutterData = args["data"] as? FlutterStandardTypedData else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing data payload", details: nil))
                return
            }
            radioCoordinator.sendBroadcast(data: flutterData.data)
            result(true)
            
        case "sendDirected":
            guard let args = call.arguments as? [String: Any],
                  let peerId = args["peerId"] as? String,
                  let flutterData = args["data"] as? FlutterStandardTypedData else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing peerId or data payload", details: nil))
                return
            }
            radioCoordinator.sendDirected(data: flutterData.data, targetPeerId: peerId)
            result(true)
            
        case "setPowerMode":
            guard let args = call.arguments as? [String: Any],
                  let modeString = args["mode"] as? String,
                  let mode = PowerMode(rawValue: modeString) else {
                result(FlutterError(code: "INVALID_ARGS", message: "Invalid power mode", details: nil))
                return
            }
            radioCoordinator.setPowerMode(mode)
            result(true)
            
        case "getConnectedPeers":
            result(Array(radioCoordinator.connectedPeers))
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - FlutterStreamHandler
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
    
    // MARK: - BLERadioCoordinatorDelegate
    
    func radioCoordinator(_ coordinator: BLERadioCoordinator, didReceivePacket data: Data, fromPeer peerId: String, rssi: Int?) {
        var payload: [String: Any] = [
            "type": "packetReceived",
            "data": FlutterStandardTypedData(bytes: data),
            "peerId": peerId
        ]
        if let rssi = rssi {
            payload["rssi"] = rssi
        }
        eventSink?(payload)
    }
    
    func radioCoordinator(_ coordinator: BLERadioCoordinator, peerConnected peerId: String) {
        eventSink?([
            "type": "peerConnected",
            "peerId": peerId
        ])
    }
    
    func radioCoordinator(_ coordinator: BLERadioCoordinator, peerDisconnected peerId: String) {
        eventSink?([
            "type": "peerDisconnected",
            "peerId": peerId
        ])
    }
    
    func radioCoordinator(_ coordinator: BLERadioCoordinator, didUpdatePowerState isPoweredOn: Bool) {
        eventSink?([
            "type": "adapterStateChanged",
            "state": isPoweredOn ? "poweredOn" : "poweredOff"
        ])
    }
}
