//
//  BLEPeripheralViewModel.swift
//  BLECentral
//
//  Created by 이재훈 on 11/11/24.
//

import CoreBluetooth
import Foundation

class PeripheralViewModel: NSObject, ChatViewModel {
    @Published var isAdvertising = false
    @Published var isConnected: Bool = false
    @Published var text = ""
    @Published var connectedCentral: CBCentral? = nil
    @Published var chats: [Chat] = []
    @Published var name: String = ""
    var userName: String = ""
    var updateText = ""
    var transferCharacteristic: CBMutableCharacteristic?
    var nameCharacteristic: CBMutableCharacteristic?
    var textPublisher: Published<String>.Publisher { $text }
    
    @Published var isSending = false
    private var isEOMPending = false
    private var dataToSend: Data?
    private var sendDataIndex = 0
    
    private var manager: CBPeripheralManager!
    
    func onAppear() {
        let options: [String: Any] = [:]
        manager = CBPeripheralManager(delegate: self, queue: .global(), options: options)
    }
    
    func toogleAdvertising() {
        if isAdvertising {
            manager.stopAdvertising()
            isAdvertising = false
        }
        else {
            startAdvertising()
        }
    }
    
    private func startAdvertising() {
        guard manager.state == .poweredOn else { return }
            
        let transferCharacteristic = CBMutableCharacteristic(
            type: BLEUUID.transferCharacteristicUUID,
            properties: [.notify, .write, .read],
            value: nil,
            permissions: [.readable, .writeable]
        )
        
        let nameCharacteristic = CBMutableCharacteristic(
            type: BLEUUID.nameCharacteristicUUID,
            properties: [.notify, .write, .read],
            value: nil,
            permissions: [.readable, .writeable]
        )
        
        let transferService = CBMutableService(type: BLEUUID.serviceUUID, primary: true)
        
        transferService.characteristics = [transferCharacteristic, nameCharacteristic]
        
        manager.add(transferService)
        
        self.transferCharacteristic = transferCharacteristic
        self.nameCharacteristic = nameCharacteristic
        
        manager.startAdvertising([
            CBAdvertisementDataLocalNameKey: name.isEmpty ? "채팅을 원해요" : name,
            CBAdvertisementDataServiceUUIDsKey: [BLEUUID.serviceUUID]
        ])
        
        isAdvertising = true
    }
    
    func cleanup() {
        connectedCentral = nil
        
        manager.removeAllServices()
        isConnected = false
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
        if let mtu = connectedCentral?.maximumUpdateValueLength {
            amountToSend = min(amountToSend, mtu)
        }
        
        let chunk = dataToSend.subdata(in: sendDataIndex..<(sendDataIndex + amountToSend))
        
        let didSend = manager.updateValue(
            chunk,
            for: transferCharacteristic,
            onSubscribedCentrals: nil
        )
        
        if didSend {
            print("didSend")
            sendDataIndex += amountToSend
            
            print(sendDataIndex, dataToSend.count)
            if sendDataIndex >= dataToSend.count {
                // 모든 데이터를 보냈으므로 다음에 EOM을 전송
                isEOMPending = true
                sendEOM()
            }
            else {
                sendNextChunk()
            }
        } else {
            // 전송에 실패했으므로 peripheralManagerIsReady를 기다림
            print("Failed to send chunk, waiting for ready signal")
        }
    }
    
    private func sendEOM() {
        guard let transferCharacteristic = transferCharacteristic else { return }
        
        let eomData = "EOM".data(using: .utf8)!
        let didSend = manager.updateValue(
            eomData,
            for: transferCharacteristic,
            onSubscribedCentrals: nil
        )
        
        if didSend {
            print("Successfully sent EOM")
            Task { @MainActor in
                chats.append(.init(myChat: true, content: text))
            }
            resetValue()
        } else {
            print("Failed to send EOM, waiting for ready signal")
        }
    }
    
    func resetValue() {
        print("resetValue")
        Task { @MainActor in
            isSending = false
            isEOMPending = false
            dataToSend = nil
            sendDataIndex = 0
            text = ""
        }
    }
}

extension PeripheralViewModel: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            print("블루투스가 켜진 상태")
        case .poweredOff:
            print("블루투스가 꺼진 상태 (control menu에서 블루투스 껐을 때)")
            Task {
                await MainActor.run {
                    isAdvertising = false
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
    
    // 특성을 구독했을 때
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        print("특성 구독")
        if characteristic.uuid == BLEUUID.transferCharacteristicUUID {
            Task { @MainActor in
                manager.stopAdvertising()
                isAdvertising = false
                isConnected = true
                
                if connectedCentral == nil {
                    connectedCentral = central
                }
            }
        }
        else if characteristic.uuid == BLEUUID.nameCharacteristicUUID,
                let nameCharacteristic {
            let name = name.data(using: .utf8)!
            manager.updateValue(name, for: nameCharacteristic, onSubscribedCentrals: nil)
        }
    }
    
    // 특성을 구독 취소했을 때
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        print("특성 구독 취소")
        Task { @MainActor in
            connectedCentral = nil
            isConnected = false
            chats.removeAll()
            resetValue()
        }
    }
    
    // 데이터를 보낼 준비가 됐을 때
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        print("데이터를 보낼 준비")
        if isSending {
            sendNextChunk()
        }
    }
    
    // Central으로부터 특성값에 Write된 데이터를 받았을 때
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        print("데이터 didReceiveWrite")
        for request in requests {

            if let value = request.value,
               let stringFromData = String(data: value, encoding: .utf8) {
                if request.characteristic.uuid == BLEUUID.nameCharacteristicUUID {
                    userName = stringFromData
                    print("Central로부터 받은 UserName: \(userName)")
                    manager.respond(to: request, withResult: .success)
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
                else {
                    updateText += stringFromData
                }
                manager.respond(to: request, withResult: .success)
            }
            else {
                manager.respond(to: request, withResult: .invalidHandle)
            }
        }
    }
}
