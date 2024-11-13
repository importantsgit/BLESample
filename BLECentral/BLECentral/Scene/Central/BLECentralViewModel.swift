//
//  BLECentralViewModel.swift
//  BLECentral
//
//  Created by 이재훈 on 11/11/24.
//

import CoreBluetooth
import Foundation

class BLECentralViewModel: NSObject, ChatViewModel {
    @Published var discoveredPeripherals: [CBPeripheral] = []
    @Published var isScanning = false
    @Published var isConnected = false
    @Published var peripheralRSSIs: [UUID: NSNumber] = [:]
    var textPublisher: Published<String>.Publisher { $text }
    @Published var chats: [Chat] = []
    @Published var userName = ""
    var updateText = ""
    var connectedPeripheral: CBPeripheral? = nil
    
    var transferCharacteristic: CBCharacteristic?
    var nameCharacteristic: CBCharacteristic?
    @Published var name: String = "" // FIXME: 해당 name UI binding
    @Published var text: String = ""
    @Published var isSending = false
    private var isEOMPending = false
    private var dataToSend: Data?
    private var sendDataIndex = 0
    
    
    private var manager: CBCentralManager!
    
    func onAppear() {
        let options: [String: Any] = [
            CBCentralManagerOptionShowPowerAlertKey: true
            // true인 경우, Manager가 scanForPeripherals 할 때 블투투스가 꺼진 상태라면 Alert을 띄움
            // 만약 커스텀 Alert을 띄우고 싶다면 해당 key <= false
        ]
        manager = CBCentralManager(delegate: self, queue: .global(), options: options)
    }
    
    func toggleScan() {
        if isScanning {
            manager.stopScan()
            discoveredPeripherals = []
            isScanning = false
        } else {
            startScanning()
        }
    }
    
    private func startScanning() {
        guard manager.state == .poweredOn else { return }
        
        let uuid = BLEUUID.serviceUUID
        manager.scanForPeripherals(
            withServices: [uuid], // 해당 서비스만 검색 (백그라운드에서 검색 가능)
            options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: true // 중복 검색 가능
            ]
        )
        isScanning = true
    }
    
    func connect(to peripheral: CBPeripheral) {
        manager.stopScan()
        isScanning = false
        
        peripheral.delegate = self
        manager.connect(peripheral, options: nil)
    }
    
    func cleanup() {
        guard let discoveredPeripheral = connectedPeripheral,
              case .connected = discoveredPeripheral.state
        else { return }
        manager.cancelPeripheralConnection(discoveredPeripheral)
        Task { @MainActor in
            chats.removeAll()
            isConnected = false
        }

    }
    
    func sendButtonTapped() {
        guard transferCharacteristic != nil else { return }
        let data = text.data(using: .utf8)!
        dataToSend = data
        sendDataIndex = 0
        isSending = true
        isEOMPending = false
        sendNextChunk()
    }
    
    private func sendNextChunk() {
        guard let transferCharacteristic = transferCharacteristic,
              let dataToSend,
              isSending
        else {
            resetValue()
            return
        }
        
        if isEOMPending {
            sendEOM()
            return
        }
        
        var amountToSend = dataToSend.count - sendDataIndex
        
        if let mtu = connectedPeripheral?.maximumWriteValueLength(for: .withResponse) {
            amountToSend = min(amountToSend, mtu)
        }
        
        let chunk = dataToSend.subdata(in: sendDataIndex..<(sendDataIndex + amountToSend))
        connectedPeripheral?.writeValue(chunk, for: transferCharacteristic, type: .withResponse)
        
        sendDataIndex += amountToSend
    }
    
    private func sendEOM() {
        guard let transferCharacteristic = transferCharacteristic
        else { return }
        
        let eomData = "EOM".data(using: .utf8)!
        
        connectedPeripheral?.writeValue(eomData, for: transferCharacteristic, type: .withResponse)
    }
    
    func resetValue() {
        print("resetValue")
        Task { @MainActor in
            isSending = false
            isEOMPending = false
            dataToSend = nil
            text = ""
            sendDataIndex = 0
        }
    }
}

extension BLECentralViewModel: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("블루투스가 켜진 상태")
        case .poweredOff:
            print("블루투스가 꺼진 상태 (control menu에서 블루투스 껐을 때)")
            Task {
                await MainActor.run {
                    isScanning = false
                    discoveredPeripherals.removeAll()
                }
            }
        case .unsupported:
            print("디바이스가 블루투스를 지원 안할 때")
        case .unauthorized:
            print("블루투스 권한을 허가 안했을 때")
        case .resetting:
            print("블루투스가 다시 세팅될 때")
        case .unknown:
            print("Bluetooth state is unknown")
        @unknown default:
            print("Unknown bluetooth state")
        }
    }
    
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        print("""
       peripheral.identifier: \(peripheral.identifier)
       peripheral.name:       \(peripheral.name)
       peripheral.service:    \(peripheral.services)
       peripheral.name:       \(peripheral.ancsAuthorized)
       peripheral.state:      \(peripheral.state)
       advertisementData:     \(advertisementData)
       rssi:                  \(RSSI)
       """)
        
        
        // RSSI 업데이트
        Task {
            await MainActor.run {
                peripheralRSSIs[peripheral.identifier] = RSSI
                // 이미 발견된 기기가 아닐 경우에만 추가
                if let index = discoveredPeripherals.firstIndex(where: { $0.identifier == peripheral.identifier }) {
                    discoveredPeripherals[index] = peripheral
                    objectWillChange.send()
                }
                else {
                    discoveredPeripherals.append(peripheral)
                    objectWillChange.send()
                }
            }
        }
        
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to: \(peripheral.name ?? peripheral.identifier.uuidString)")
        Task { @MainActor in
            connectedPeripheral = peripheral
            isConnected = true
        }
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
        Task { @MainActor in
            isConnected = false
            discoveredPeripherals.removeAll()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        print("didDisconnectPeripheral")
        Task { @MainActor in
            isConnected = false
            discoveredPeripherals.removeAll()
        }
    }
    
    func centralManager(_ central: CBCentralManager, connectionEventDidOccur event: CBConnectionEvent, for peripheral: CBPeripheral) {
        print("connectionEventDidOccur")
    }
}

extension BLECentralViewModel: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("Error discovering services: \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else { return }
        
        for service in services {
            print("Discovered service: \(service.uuid)")
            peripheral.discoverCharacteristics([BLEUUID.transferCharacteristicUUID, BLEUUID.nameCharacteristicUUID], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error = error {
            print("Error discovering characteristics: \(error.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            print("Found characteristic: \(characteristic.uuid)")
            
            if characteristic.properties.contains(.notify) {
                if characteristic.uuid == BLEUUID.transferCharacteristicUUID {
                    transferCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                }
                else if characteristic.uuid == BLEUUID.nameCharacteristicUUID {
                    nameCharacteristic = characteristic
                    peripheral.readValue(for: characteristic)
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error = error {
            print("Error updating value: \(error.localizedDescription)")
            return
        }
        
        guard let characteristicData = characteristic.value,
              let stringFromData = String(data: characteristicData, encoding: .utf8)
        else { return }
        
        print("Characteristic: \(characteristic.uuid), Value: \(stringFromData)")
        
        if characteristic.uuid == BLEUUID.nameCharacteristicUUID,
           let nameCharacteristic {
            Task { @MainActor in
                print("Peripheral에서 받은 UserName: \(stringFromData)")
                userName = stringFromData
                let nameData = name.data(using: .utf8)!
                connectedPeripheral?.writeValue(nameData, for: nameCharacteristic, type: .withoutResponse)
            }
            return
        }
        if stringFromData == "EOM" {
            Task { @MainActor in
                chats.append(.init(
                    myChat: false,
                    userName: userName,
                    content: updateText
                ))
                updateText = ""
            }
        }
        else if stringFromData == "CLEANUP" {
            cleanup()
        }
        else {
            updateText += stringFromData
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        if let error = error {
            print("Failed to send Data, waiting for ready signal \(error)")
            resetValue()
        }
        else {
            if isEOMPending {
                print("successs send Data EOMPending")
                Task { @MainActor in
                    chats.append(.init(
                        myChat: true,
                        content: text
                    )
                    )
                }
                resetValue()
            }
            else if let dataToSend,
                    sendDataIndex >= dataToSend.count {
                print("successs send Data sendEOM")
                isEOMPending = true
                sendEOM()
            }
            else {
                print("successs send Data")
                sendNextChunk()
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        if invalidatedServices.isEmpty {
            print("연결된 Service가 없습니다.")
            cleanup()
        }
    }
}

struct Chat: Identifiable, Equatable {
    let id: UUID = UUID()
    let myChat: Bool
    let userName: String?
    let content: String
    
    init(myChat: Bool, userName: String? = nil, content: String) {
        self.myChat = myChat
        self.userName = userName
        self.content = content
    }
}
