//
//  BLECentralViewModel.swift
//  BLECentral
//
//  Created by 이재훈 on 11/11/24.
//

import CoreBluetooth
import Foundation

class BLECentralViewModel: NSObject, ChatViewModel {
    /**
     특성 정보
     
     - CBCharacteristic은 remote peripheral의 Service 특성을 나타냄 (받는 쪽에서 사용할 때 사용)
     - CBMutableCharacteristic은 peripheral의 특성을 정의할 때 사용
     - 따라서 Central과 Peripheral가 사용하는 객체가 다름
    */
    private struct Characteristics {
        var transferCharacteristic: CBCharacteristic?
        var nameCharacteristic: CBCharacteristic?
        
        init(
            transferCharacteristic: CBCharacteristic? = nil,
            nameCharacteristic: CBCharacteristic? = nil
        ) {
            self.transferCharacteristic = transferCharacteristic
            self.nameCharacteristic = nameCharacteristic
        }
    }
    
    private struct MessageSendingState {
        var isSending: Bool
        var isEOMPending: Bool
        var dataToSend: Data?
        var sendDataIndex: Int
        
        init(
            isSending: Bool = false,
            isEOMPending: Bool = false,
            dataToSend: Data? = nil,
            sendDataIndex: Int = 0
        ) {
            self.isSending = isSending
            self.isEOMPending = isEOMPending
            self.dataToSend = dataToSend
            self.sendDataIndex = sendDataIndex
        }
    }
    
    // 중앙 장치에서 사용하는 manager
    private var manager: CBCentralManager!
    
    @Published var name: String = "Central"
    @Published var discoveredPeripherals: [CBPeripheral] = []
    @Published var peripheralRSSIs: [UUID: NSNumber] = [:]
    @Published var isScanning = false
    
    private var connectedPeripheral: CBPeripheral? = nil
    private var characteristics: Characteristics = .init()
    @Published var isConnected = false
    
    var textPublisher: Published<String>.Publisher { $text }
    @Published var text: String = ""
    @Published var chats: [Chat] = []
    @Published var userName: String = ""
    var updateText = ""
    
    private var messageSendingState: MessageSendingState = .init()
    
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
    
    // 보내기 버튼 클릭 시 이벤트 처리 (초기 설정)
    func sendButtonTapped() {
        guard characteristics.transferCharacteristic != nil else { return }
        let data = text.data(using: .utf8)!
        messageSendingState.dataToSend = data
        messageSendingState.sendDataIndex = 0
        messageSendingState.isSending = true
        messageSendingState.isEOMPending = false
        sendNextChunk()
    }
    
    // 보내는 버튼 클릭 시 / sendNextChunk 내부 / didUpdateValueFor 시 호출
    private func sendNextChunk() {
        guard let transferCharacteristic = characteristics.transferCharacteristic,
              let dataToSend = messageSendingState.dataToSend,
              messageSendingState.isSending
        else {
            resetValue()
            return
        }
        
        if messageSendingState.isEOMPending {
            sendEOM()
            return
        }
        
        var amountToSend = dataToSend.count - messageSendingState.sendDataIndex
        
        if let mtu = connectedPeripheral?.maximumWriteValueLength(for: .withResponse) {
            amountToSend = min(amountToSend, mtu)
        }
        
        let chunk = dataToSend.subdata(in: messageSendingState.sendDataIndex..<(messageSendingState.sendDataIndex + amountToSend))
        connectedPeripheral?.writeValue(chunk, for: transferCharacteristic, type: .withResponse)
        
        messageSendingState.sendDataIndex += amountToSend
    }
    
    private func sendEOM() {
        guard let transferCharacteristic = characteristics.transferCharacteristic
        else { return }
        
        let eomData = "EOM".data(using: .utf8)!
        
        connectedPeripheral?.writeValue(eomData, for: transferCharacteristic, type: .withResponse)
    }
    
    func resetValue() {
        print("resetValue")
        Task { @MainActor in
            messageSendingState.isSending = false
            messageSendingState.isEOMPending = false
            messageSendingState.dataToSend = nil
            messageSendingState.sendDataIndex = 0
            text = ""
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
                    discoveredPeripherals.append(contentsOf: [CBPeripheral](repeating: peripheral, count: 10))
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
    // peripheral에서 AD하는 Service를 발견했을 때
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("Error discovering services: \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else { return }
        
        for service in services {
            print("Discovered service: \(service.uuid)")
            peripheral.discoverCharacteristics(
                [BLEUUID.transferCharacteristicUUID, BLEUUID.nameCharacteristicUUID],
                for: service
            )
        }
    }
    
    // discoverCharacteristics를 통해 발견된 Characteristics
    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error = error {
            print("Error discovering characteristics: \(error.localizedDescription)")
            return
        }
        
        guard let foundCharacteristics = service.characteristics else { return }
        
        for foundCharacteristic in foundCharacteristics {
            if foundCharacteristic.uuid == BLEUUID.transferCharacteristicUUID,
               foundCharacteristic.properties.contains(.notify) {
                characteristics.transferCharacteristic = foundCharacteristic
                peripheral.setNotifyValue(true, for: foundCharacteristic)
            }
            else if foundCharacteristic.uuid == BLEUUID.nameCharacteristicUUID,
                    foundCharacteristic.properties.contains(.read) {
                characteristics.nameCharacteristic = foundCharacteristic
                peripheral.readValue(for: foundCharacteristic)
            }
        }
    }
    
    // 특성값이 업데이트될 때 호출되는 함수/
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
           let nameCharacteristic = characteristics.nameCharacteristic {
            Task { @MainActor in
                print("Peripheral에서 받은 UserName: \(stringFromData)")
                userName = stringFromData
                let nameData = name.data(using: .utf8)!
                connectedPeripheral?.writeValue(nameData, for: nameCharacteristic, type: .withoutResponse)
            }
            return
        }
        switch stringFromData {
        case "EOM":
            Task { @MainActor in
                chats.append(.init(
                    myChat: false,
                    content: updateText
                ))
                updateText = ""
            }
        default:
            updateText += stringFromData
        }
    }
    
    // 특성값 쓰기 완료 시 호출되는 함수
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        if let error = error {
            print("Failed to send Data, waiting for ready signal \(error)")
            resetValue()
        }
        else {
            if messageSendingState.isEOMPending {
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
            else if let dataToSend = messageSendingState.dataToSend,
                    messageSendingState.sendDataIndex >= dataToSend.count {
                print("successs send Data sendEOM")
                messageSendingState.isEOMPending = true
                sendEOM()
            }
            else {
                print("successs send Data")
                sendNextChunk()
            }
        }
    }
    
    // 블루투스 서비스가 수정될 때 호출되는 함수
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
    let content: String
    
    init(myChat: Bool, content: String) {
        self.myChat = myChat
        self.content = content
    }
}
