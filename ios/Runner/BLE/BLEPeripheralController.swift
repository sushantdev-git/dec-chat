import Foundation
import CoreBluetooth

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
    
    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [
            CBPeripheralManagerOptionShowPowerAlertKey: true
        ])
    }
    
    func startAdvertising() {
        guard peripheralManager.state == .poweredOn else { return }
        setupService()
        
        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [BLEConstants.serviceUUID],
            CBAdvertisementDataLocalNameKey: "DecChat"
        ]
        peripheralManager.startAdvertising(advertisementData)
        isAdvertising = true
    }
    
    func stopAdvertising() {
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
        if isReady && isAdvertising {
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
