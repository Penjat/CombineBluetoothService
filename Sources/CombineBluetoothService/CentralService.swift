import CoreBluetooth
import Combine
import GenericService

public protocol CentralService: GenericService.Service {
    typealias Intent = CentralServiceIntent
    typealias Event = CentralServiceEvent
    typealias State = CBManagerState
    typealias Configuration = Void?
    
    var input: PassthroughSubject<Intent, Never> { get }
    var events: PassthroughSubject<Event, Never> { get }
    var state: CurrentValueSubject<State, Never> { get }
}

public enum CentralServiceEvent {
    case didDiscover(peripheral: CBPeripheral)
    case didConnect(peripheral: CBPeripheral)
    case didDisconnect(peripheral: CBPeripheral)
    case recievedData(peripheralId: UUID, characteristicId: CBUUID, data: Data)
    case scanning(Bool)
}

public enum CentralServiceIntent {
    case startScanning
    case stopScanning
    case send(peripheralId: UUID, serviceUUID: CBUUID, characteristicId: CBUUID, data: Data)
}

public class BluetoothCentralService: NSObject, CentralService {
    
    public let input = PassthroughSubject<Intent, Never>()
    public let events = PassthroughSubject<Event, Never>()
    public let state = CurrentValueSubject<State, Never>(.unknown)
    public let configuration = CurrentValueSubject<Configuration, Never>(nil)
    
    private var centralManager: CBCentralManager!
    private var serviceIDs: [CBUUID]!
    private var characteristicIDs: [CBUUID]!
    private var peripherals = [CBPeripheral]()
    private var bag = Set<AnyCancellable>()
    
    public init(serviceIDs: [CBUUID], characteristicIDs: [CBUUID]) {
        super.init()
        print("creating...")
        self.serviceIDs = serviceIDs
        self.characteristicIDs = characteristicIDs
        
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: true])
        
        input.sink { [weak self] in self?.process(intent: $0)}.store(in: &bag)
        
    }
    
    internal func process(intent: CentralServiceIntent) {
        switch intent {
        case .startScanning:
            centralManager.scanForPeripherals(withServices: serviceIDs,
                                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            events.send(.scanning(true))
            
        case .stopScanning:
            centralManager.stopScan()
            events.send(.scanning(false))
            
        case .send(peripheralId: let peripheralId, serviceUUID: let serviceUUID, characteristicId: let characteristicId, data: let data):
            print("sending data: \(data)")
            send(peripheralUUID: peripheralId, serviceUUID: serviceUUID, characteristicId: characteristicId, data: data)
        }
    }
    
    private func send(peripheralUUID: UUID, serviceUUID: CBUUID, characteristicId: CBUUID, data: Data) {
        guard
            let peripheral = peripherals.first(where: { $0.identifier == peripheralUUID }),
            let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }),
            let characteristic = service.characteristics?.first(where: { $0.uuid == characteristicId })
        else {
            return
        }
        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        print("Data was sent")
    }
    
    private func connectToPeripheral(uuid: UUID, connect: Bool) {
        for peripheral in peripherals where uuid == peripheral.identifier {
            if connect {
                centralManager.connect(peripheral, options: nil)
            } else {
                centralManager.cancelPeripheralConnection(peripheral)
            }
        }
    }
    
    private func connectToCharacteristic(uuid: CBUUID, connect: Bool) {
        
        peripherals.forEach { peripheral in
            peripheral.services?.forEach{ service in
                guard let serviceCharacteristics = service.characteristics else {
                    return
                }
                for characteristic in serviceCharacteristics where uuid == characteristic.uuid {
                    peripheral.setNotifyValue(connect, for: characteristic)
                    print("discovered characteristic: \(characteristic) \(characteristic.uuid)")
                }
            }
        }
    }
}

extension BluetoothCentralService: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state.send(centralManager.state)
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if !peripherals.contains(peripheral) {
            centralManager.connect(peripheral, options: nil)
            peripherals.append(peripheral)
            events.send(.didDiscover(peripheral: peripheral))
            
        } else if peripheral.state == .disconnected {
            centralManager.connect(peripheral, options: nil)
            events.send(.didDiscover(peripheral: peripheral))
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices(serviceIDs)
        events.send(.didConnect(peripheral: peripheral))
    }
}

extension BluetoothCentralService: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        for service in invalidatedServices where serviceIDs.contains(service.uuid) {
            peripheral.discoverServices(serviceIDs)
        }
        
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("\(error)")
            return
        }
        
        guard let peripheralServices = peripheral.services else { return }
        for service in peripheralServices {
            peripheral.discoverCharacteristics(nil, for: service)
            print("discovered service: \(service)")
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        events.send(.didDisconnect(peripheral: peripheral))
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("\(error)")
            return
        }
        
        guard let serviceCharacteristics = service.characteristics else {
            return
        }
        
        for characteristic in serviceCharacteristics where characteristicIDs.contains(characteristic.uuid) {
            peripheral.setNotifyValue(true, for: characteristic)
            events.send(.didConnect(peripheral: peripheral))
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Error receiving data: \(error.localizedDescription)")
            return

        }

        guard let characteristicData = characteristic.value else {
            print("No data received")
            return

        }
        
        events.send(.recievedData(peripheralId: peripheral.identifier, characteristicId: characteristic.uuid, data: characteristicData))
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        
        if let error {
            print("\(error)")
            return
        }
        
        if characteristic.isNotifying {
            // Notification has started
            
        } else {
            // Notification has stopped, so disconnect from the peripheral
            
//            cleanup()
        }
        
    }
    
    public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        
    }
}
