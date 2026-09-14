import Cocoa
import FlutterMacOS
import Foundation
import CoreBluetooth

enum BLEConstants {
    static let serviceUUID = CBUUID(string: "0000FDC7-0000-1000-8000-00805F9B34FB")
    static let packetCharacteristicUUID = CBUUID(string: "00002A06-0000-1000-8000-00805F9B34FB")
    
    static let controlChannelName = "com.bitchat.mesh/ble_control"
    static let eventChannelName = "com.bitchat.mesh/ble_events"
    
    static let targetMTU: Int = 512
}

enum PowerMode: String {
    case active = "active"
    case balanced = "balanced"
    case background = "background"
}

protocol BLEPeripheralDelegate: AnyObject {
    func peripheralController(_ controller: BLEPeripheralController, didReceivePacket data: Data, fromCentral central: CBCentral)
    func peripheralController(_ controller: BLEPeripheralController, centralConnected central: CBCentral)
    func peripheralController(_ controller: BLEPeripheralController, centralDisconnected central: CBCentral)
    func peripheralController(_ controller: BLEPeripheralController, didUpdateState isReady: Bool)
}

class BLEPeripheralController: NSObject, CBPeripheralManagerDelegate {
    weak var delegate: BLEPeripheralDelegate?
    
    private var peripheralManager: CBPeripheralManager!
    private var transferCharacteristic: CBMutableCharacteristic?
    private var subscribedCentrals = Set<CBCentral>()
    
    private var isAdvertising = false
    private var shouldBeAdvertising = false
    
    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [
            CBPeripheralManagerOptionShowPowerAlertKey: true
        ])
    }
    
    func startAdvertising() {
        shouldBeAdvertising = true
        guard peripheralManager.state == .poweredOn else { return }
        setupService()
        
        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [BLEConstants.serviceUUID],
            CBAdvertisementDataLocalNameKey: "Grid"
        ]
        peripheralManager.startAdvertising(advertisementData)
        isAdvertising = true
    }
    
    func stopAdvertising() {
        shouldBeAdvertising = false
        peripheralManager.stopAdvertising()
        isAdvertising = false
        subscribedCentrals.removeAll()
    }
    
    private func setupService() {
        peripheralManager.removeAllServices()
        
        let properties: CBCharacteristicProperties = [.write, .writeWithoutResponse, .notify]
        let permissions: CBAttributePermissions = [.writeable]
        
        let characteristic = CBMutableCharacteristic(
            type: BLEConstants.packetCharacteristicUUID,
            properties: properties,
            value: nil,
            permissions: permissions
        )
        self.transferCharacteristic = characteristic
        
        let service = CBMutableService(type: BLEConstants.serviceUUID, primary: true)
        service.characteristics = [characteristic]
        peripheralManager.add(service)
    }
    
    func broadcastPacket(_ data: Data) -> Bool {
        guard let characteristic = transferCharacteristic, !subscribedCentrals.isEmpty else {
            return false
        }
        return peripheralManager.updateValue(data, for: characteristic, onSubscribedCentrals: nil)
    }
    
    func sendDirectedPacket(_ data: Data, toCentralIdentifier idString: String) -> Bool {
        guard let characteristic = transferCharacteristic else { return false }
        let targetCentrals = subscribedCentrals.filter { $0.identifier.uuidString == idString }
        guard !targetCentrals.isEmpty else { return false }
        return peripheralManager.updateValue(data, for: characteristic, onSubscribedCentrals: Array(targetCentrals))
    }
    
    // MARK: - CBPeripheralManagerDelegate
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        let isReady = peripheral.state == .poweredOn
        delegate?.peripheralController(self, didUpdateState: isReady)
        if isReady && shouldBeAdvertising {
            startAdvertising()
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        subscribedCentrals.insert(central)
        delegate?.peripheralController(self, centralConnected: central)
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        subscribedCentrals.remove(central)
        delegate?.peripheralController(self, centralDisconnected: central)
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if let value = request.value {
                delegate?.peripheralController(self, didReceivePacket: value, fromCentral: request.central)
            }
            peripheral.respond(to: request, withResult: .success)
        }
    }
}

protocol BLECentralDelegate: AnyObject {
    func centralController(_ controller: BLECentralController, didReceivePacket data: Data, fromPeripheral peripheral: CBPeripheral, rssi: NSNumber?)
    func centralController(_ controller: BLECentralController, peripheralConnected peripheral: CBPeripheral)
    func centralController(_ controller: BLECentralController, peripheralDisconnected peripheral: CBPeripheral)
    func centralController(_ controller: BLECentralController, didUpdateState isReady: Bool)
}

class BLECentralController: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    weak var delegate: BLECentralDelegate?
    
    private var centralManager: CBCentralManager!
    private var connectedPeripherals = [UUID: CBPeripheral]()
    private var peerCharacteristics = [UUID: CBCharacteristic]()
    
    private var isScanning = false
    private var shouldBeScanning = false
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [
            CBCentralManagerOptionShowPowerAlertKey: true,
            CBCentralManagerOptionRestoreIdentifierKey: "com.bitchat.mesh.central_restore"
        ])
    }
    
    func startScanning() {
        shouldBeScanning = true
        guard centralManager.state == .poweredOn else { return }
        isScanning = true
        centralManager.scanForPeripherals(
            withServices: [BLEConstants.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }
    
    func stopScanning() {
        shouldBeScanning = false
        centralManager.stopScan()
        isScanning = false
    }
    
    func disconnectAll() {
        stopScanning()
        for (_, peripheral) in connectedPeripherals {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        connectedPeripherals.removeAll()
        peerCharacteristics.removeAll()
    }
    
    func broadcastPacket(_ data: Data) {
        for (_, peripheral) in connectedPeripherals {
            if let characteristic = peerCharacteristics[peripheral.identifier] {
                let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
                peripheral.writeValue(data, for: characteristic, type: writeType)
            }
        }
    }
    
    func sendDirectedPacket(_ data: Data, toPeripheralUUID uuidString: String) -> Bool {
        guard let uuid = UUID(uuidString: uuidString),
              let peripheral = connectedPeripherals[uuid],
              let characteristic = peerCharacteristics[uuid] else {
            return false
        }
        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(data, for: characteristic, type: writeType)
        return true
    }
    
    // MARK: - CBCentralManagerDelegate
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let isReady = central.state == .poweredOn
        delegate?.centralController(self, didUpdateState: isReady)
        if isReady && shouldBeScanning {
            startScanning()
        }
    }
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for peripheral in peripherals {
                connectedPeripherals[peripheral.identifier] = peripheral
                peripheral.delegate = self
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard connectedPeripherals[peripheral.identifier] == nil else { return }
        connectedPeripherals[peripheral.identifier] = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([BLEConstants.serviceUUID])
        delegate?.centralController(self, peripheralConnected: peripheral)
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedPeripherals.removeValue(forKey: peripheral.identifier)
        peerCharacteristics.removeValue(forKey: peripheral.identifier)
        delegate?.centralController(self, peripheralDisconnected: peripheral)
        
        // Resume scan if enabled
        if isScanning {
            centralManager.scanForPeripherals(withServices: [BLEConstants.serviceUUID], options: nil)
        }
    }
    
    // MARK: - CBPeripheralDelegate
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == BLEConstants.serviceUUID {
            peripheral.discoverCharacteristics([BLEConstants.packetCharacteristicUUID], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics where characteristic.uuid == BLEConstants.packetCharacteristicUUID {
            peerCharacteristics[peripheral.identifier] = characteristic
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        delegate?.centralController(self, didReceivePacket: data, fromPeripheral: peripheral, rssi: nil)
    }
}

protocol BLERadioCoordinatorDelegate: AnyObject {
    func radioCoordinator(_ coordinator: BLERadioCoordinator, didReceivePacket data: Data, fromPeer peerId: String, rssi: Int?)
    func radioCoordinator(_ coordinator: BLERadioCoordinator, peerConnected peerId: String)
    func radioCoordinator(_ coordinator: BLERadioCoordinator, peerDisconnected peerId: String)
    func radioCoordinator(_ coordinator: BLERadioCoordinator, didUpdatePowerState isPoweredOn: Bool)
}

class BLERadioCoordinator: BLEPeripheralDelegate, BLECentralDelegate {
    weak var delegate: BLERadioCoordinatorDelegate?
    
    private let peripheralController: BLEPeripheralController
    private let centralController: BLECentralController
    
    private var powerMode: PowerMode = .active
    private var dutyCycleTimer: Timer?
    private var isRadioActiveCycle = true
    
    private var isCentralReady = false
    private var isPeripheralReady = false
    
    private(set) var connectedPeers = Set<String>()
    
    init() {
        peripheralController = BLEPeripheralController()
        centralController = BLECentralController()
        
        peripheralController.delegate = self
        centralController.delegate = self
    }
    
    func start(mode: PowerMode = .active) {
        self.powerMode = mode
        peripheralController.startAdvertising()
        centralController.startScanning()
        applyDutyCycle()
    }
    
    func stop() {
        dutyCycleTimer?.invalidate()
        dutyCycleTimer = nil
        
        peripheralController.stopAdvertising()
        centralController.disconnectAll()
        connectedPeers.removeAll()
    }
    
    func setPowerMode(_ mode: PowerMode) {
        self.powerMode = mode
        applyDutyCycle()
    }
    
    func sendBroadcast(data: Data) {
        centralController.broadcastPacket(data)
        _ = peripheralController.broadcastPacket(data)
    }
    
    func sendDirected(data: Data, targetPeerId: String) {
        if !centralController.sendDirectedPacket(data, toPeripheralUUID: targetPeerId) {
            _ = peripheralController.sendDirectedPacket(data, toCentralIdentifier: targetPeerId)
        }
    }
    
    private func applyDutyCycle() {
        dutyCycleTimer?.invalidate()
        dutyCycleTimer = nil
        
        switch powerMode {
        case .active:
            // Continuous scanning and advertising
            peripheralController.startAdvertising()
            centralController.startScanning()
            
        case .balanced:
            // 15s scan on, 15s idle
            scheduleDutyCycle(activeDuration: 15.0, idleDuration: 15.0)
            
        case .background:
            // 5s scan on, 55s idle
            scheduleDutyCycle(activeDuration: 5.0, idleDuration: 55.0)
        }
    }
    
    private func scheduleDutyCycle(activeDuration: TimeInterval, idleDuration: TimeInterval) {
        isRadioActiveCycle = true
        centralController.startScanning()
        
        dutyCycleTimer = Timer.scheduledTimer(withTimeInterval: activeDuration, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.centralController.stopScanning()
            self.isRadioActiveCycle = false
            
            self.dutyCycleTimer = Timer.scheduledTimer(withTimeInterval: idleDuration, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.applyDutyCycle()
            }
        }
    }
    
    // MARK: - BLEPeripheralDelegate
    
    func peripheralController(_ controller: BLEPeripheralController, didReceivePacket data: Data, fromCentral central: CBCentral) {
        delegate?.radioCoordinator(self, didReceivePacket: data, fromPeer: central.identifier.uuidString, rssi: nil)
    }
    
    func peripheralController(_ controller: BLEPeripheralController, centralConnected central: CBCentral) {
        let id = central.identifier.uuidString
        connectedPeers.insert(id)
        delegate?.radioCoordinator(self, peerConnected: id)
    }
    
    func peripheralController(_ controller: BLEPeripheralController, centralDisconnected central: CBCentral) {
        let id = central.identifier.uuidString
        connectedPeers.remove(id)
        delegate?.radioCoordinator(self, peerDisconnected: id)
    }
    
    func peripheralController(_ controller: BLEPeripheralController, didUpdateState isReady: Bool) {
        isPeripheralReady = isReady
        checkPowerState()
    }
    
    // MARK: - BLECentralDelegate
    
    func centralController(_ controller: BLECentralController, didReceivePacket data: Data, fromPeripheral peripheral: CBPeripheral, rssi: NSNumber?) {
        delegate?.radioCoordinator(self, didReceivePacket: data, fromPeer: peripheral.identifier.uuidString, rssi: rssi?.intValue)
    }
    
    func centralController(_ controller: BLECentralController, peripheralConnected peripheral: CBPeripheral) {
        let id = peripheral.identifier.uuidString
        connectedPeers.insert(id)
        delegate?.radioCoordinator(self, peerConnected: id)
    }
    
    func centralController(_ controller: BLECentralController, peripheralDisconnected peripheral: CBPeripheral) {
        let id = peripheral.identifier.uuidString
        connectedPeers.remove(id)
        delegate?.radioCoordinator(self, peerDisconnected: id)
    }
    
    func centralController(_ controller: BLECentralController, didUpdateState isReady: Bool) {
        isCentralReady = isReady
        checkPowerState()
    }
    
    private func checkPowerState() {
        let overallReady = isCentralReady && isPeripheralReady
        delegate?.radioCoordinator(self, didUpdatePowerState: overallReady)
    }
}

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

class MainFlutterWindow: NSWindow {
  private var bleChannel: BlePlatformChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    bleChannel = BlePlatformChannel(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
