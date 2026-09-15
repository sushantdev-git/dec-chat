import Foundation
import CoreBluetooth

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
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [
            CBCentralManagerOptionShowPowerAlertKey: true,
            CBCentralManagerOptionRestoreIdentifierKey: "com.bitchat.mesh.central_restore"
        ])
    }
    
    func startScanning(allowDuplicates: Bool = false) {
        guard centralManager.state == .poweredOn else { return }
        isScanning = true
        centralManager.scanForPeripherals(
            withServices: [BLEConstants.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: allowDuplicates]
        )
    }
    
    func retrieveConnectedPeripherals() -> [CBPeripheral] {
        guard centralManager.state == .poweredOn else { return [] }
        let peripherals = centralManager.retrieveConnectedPeripherals(withServices: [BLEConstants.serviceUUID])
        for peripheral in peripherals {
            if connectedPeripherals[peripheral.identifier] == nil {
                connectedPeripherals[peripheral.identifier] = peripheral
                peripheral.delegate = self
                centralManager.connect(peripheral, options: nil)
            }
        }
        return peripherals
    }
    
    func stopScanning() {
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
        if isReady && isScanning {
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
