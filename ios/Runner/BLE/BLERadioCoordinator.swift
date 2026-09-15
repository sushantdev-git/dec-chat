import Foundation
import CoreBluetooth

enum PowerMode: String {
    case active = "active"
    case balanced = "balanced"
    case background = "background"
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
    
    func restartScan() {
        self.powerMode = .active
        dutyCycleTimer?.invalidate()
        dutyCycleTimer = nil
        
        peripheralController.startAdvertising()
        _ = centralController.retrieveConnectedPeripherals()
        centralController.stopScanning()
        centralController.startScanning(allowDuplicates: true)
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
