import CoreBluetooth
import Foundation

/// Forwards every callback into the actor. CoreBluetooth calls these on the actor's own queue, so
/// `assumeIsolated` holds. Only `Sendable` facts are read here and passed in; the actor retrieves
/// the peripheral and characteristics it needs from its own central.
final nonisolated class CentralDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var transport: PrinterTransport?

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        transport?.assumeIsolated { $0.didUpdateState(state) }
    }

    func centralManager(
        _: CBCentralManager, didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any], rssi _: NSNumber
    ) {
        let id = peripheral.identifier
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        transport?.assumeIsolated { $0.didDiscover(id: id, name: name) }
    }

    func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let id = peripheral.identifier
        transport?.assumeIsolated { $0.didConnect(id) }
    }

    func centralManager(
        _: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?
    ) {
        let id = peripheral.identifier
        let reason = error?.localizedDescription
        transport?.assumeIsolated { $0.didFailToConnect(id, reason: reason) }
    }

    func centralManager(
        _: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error _: (any Error)?
    ) {
        let id = peripheral.identifier
        transport?.assumeIsolated { $0.didDisconnect(id) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        let id = peripheral.identifier
        let failure = error?.localizedDescription
        transport?.assumeIsolated { $0.didDiscoverServices(id, failure: failure) }
    }

    func peripheral(
        _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?
    ) {
        let id = peripheral.identifier
        let serviceUUID = service.uuid.uuidString
        let failure = error?.localizedDescription
        transport?.assumeIsolated { $0.didDiscoverCharacteristics(id, serviceUUID: serviceUUID, failure: failure) }
    }

    func peripheral(
        _: CBPeripheral, didWriteValueFor _: CBCharacteristic, error: (any Error)?
    ) {
        let failure = error?.localizedDescription
        transport?.assumeIsolated { $0.didWrite(failure: failure) }
    }

    func peripheral(
        _: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?
    ) {
        let uuid = characteristic.uuid.uuidString
        let value = error == nil ? characteristic.value : nil
        transport?.assumeIsolated { $0.didUpdateValue(characteristicUUID: uuid, value: value) }
    }
}
