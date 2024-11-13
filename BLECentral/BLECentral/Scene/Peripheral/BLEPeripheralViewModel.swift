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
        isAdvertising ? manager.stopAdvertising() : startAdvertising()
        isAdvertising = !isAdvertising
    }
}

// Advertising 관련 메서드
private extension PeripheralViewModel {
    
    // 데이터를 담을 Characteristics
    func makeCharacteristics() -> [CBMutableCharacteristic] {
        let transferCharacteristic = CBMutableCharacteristic(
            type: BLEUUID.transferCharacteristicUUID,
            properties: [.notify, .write, .read],
            value: nil,
            permissions: [.readable, .writeable]
        )
        
        let nameCharacteristic = CBMutableCharacteristic(
            type: BLEUUID.nameCharacteristicUUID,
            properties: [.notify, .writeWithoutResponse, .read],
            value: nil,
            permissions: [.readable, .writeable]
        )
        
        self.transferCharacteristic = transferCharacteristic
        self.nameCharacteristic = nameCharacteristic
        
        return [transferCharacteristic, nameCharacteristic]
    }
    
    // Characteristics를 담을 Service
    func makeService() -> CBMutableService {
        let transferService = CBMutableService(type: BLEUUID.serviceUUID, primary: true)
        transferService.characteristics = makeCharacteristics()
        
        return transferService
    }
    
    // startAdvertising
    func startAdvertising() {
        guard manager.state == .poweredOn else { return }
        
        manager.add(makeService())
        
        manager.startAdvertising([
            CBAdvertisementDataLocalNameKey: name.isEmpty ? "채팅을 원해요" : name,
            CBAdvertisementDataServiceUUIDsKey: [BLEUUID.serviceUUID]
        ])
    }
}

extension PeripheralViewModel {
    func cleanup() {
        connectedCentral = nil
        manager.removeAllServices()
        isConnected = false
    }
}

// 데이터를 보내는 메서드
extension PeripheralViewModel {
    func sendButtonTapped() {
        guard transferCharacteristic != nil else { return }
        isSending = true
        
        let data = text.data(using: .utf8)!
        dataToSend = data
        sendDataIndex = 0
        
        isEOMPending = false
        
        // 데이터 보내기
        sendNextChunk()
    }
    
    // 데이터는 보낼 수 있는 데이터 크기만큼 잘라서 보내는 작업을 무수히 반복해 보냄
    // 이 예시에서는 문장의 끝을 알리기 위해 데이터를 다 보내면 EOM이라는 데이터를 보냄
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
            updateText = ""
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
            Task { @MainActor in
                isAdvertising = false
                isConnected = false
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
    
    /**
    Central이 특성을 read할 경우 호출
    - request에 read될 데이터를 담아서 보낸다.
    - 이 예시에서는 nameCharacteristic을 read하여 Central에 데이터를 보냄
    */
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        if request.characteristic.uuid == BLEUUID.nameCharacteristicUUID {
            request.value = name.data(using: .utf8)
            manager.respond(to: request, withResult: .success)
        }
        else {
            manager.respond(to: request, withResult: .invalidHandle)
        }
    }
    /**
    Central이 특성을 구독했을 때 호출
    - 구독 시 처리 로직을 구현한다.
    - 이 예시에서는 transferCharacteristic을 구독하여 Central이 Peripheral의 데이터가 update되면 읽음
     */
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
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
    }
    
    // 특성을 구독 취소했을 때
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        Task { @MainActor in
            connectedCentral = nil
            isConnected = false
            chats.removeAll()
            resetValue()
        }
    }
    
    /**
    데이터를 보낼 준비가 됐을 때 호출되는 메서드
    - updateValue가 false를 반환한 경우(이전 전송이 아직 처리 중일 때) 자동으로 호출됨
    - 너무 빠르게 연속적으로 데이터를 update할 경우,
      이전 전송이 완료되지 않아 실패한 update들은 이 메서드가 호출된 후 재시도할 수 있음
    */
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
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
                switch request.characteristic.uuid {
                case BLEUUID.nameCharacteristicUUID:
                    userName = stringFromData
                    // nameCharacteristic은 writeWithoutResponse 값을 가지고 있기 때문에 respond를 보낼 필요가 없다.
                    
                case BLEUUID.transferCharacteristicUUID:
                    if stringFromData == "EOM" {
                        Task { @MainActor in
                            chats.append(
                                .init(
                                    myChat: false,
                                    userName: userName,
                                    content: updateText
                                )
                            )
                            updateText = ""
                        }
                    }
                    else {
                        updateText += stringFromData
                    }
                    manager.respond(to: request, withResult: .success)

                default:
                    fatalError("잘못된 Write한 값이 들어왔어요")
                }
                return
            }
        }
    }
}
