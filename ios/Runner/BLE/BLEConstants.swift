import Foundation
import CoreBluetooth

enum BLEConstants {
    static let serviceUUID = CBUUID(string: "0000FDC7-0000-1000-8000-00805F9B34FB")
    static let packetCharacteristicUUID = CBUUID(string: "00002A06-0000-1000-8000-00805F9B34FB")
    
    static let controlChannelName = "com.bitchat.mesh/ble_control"
    static let eventChannelName = "com.bitchat.mesh/ble_events"
    
    static let targetMTU: Int = 512
}
