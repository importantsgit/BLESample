# BLESample

## 개념 정리

### BLE 연결 과정: 스캔 / AD
BLE 통신에서 기기 간 데이터를 주고받기 위해서는 연결 과정이 필수임.<br>
Peripheral이 데이터를 Advertising(광고)하고, Central이 이를 스캔하여 연결함.<br>
<br>
1. 서비스와 특성 정의
Advertising에 사용할 서비스와 특성을 설정.<br>
CBMutableService와 CBMutableCharacteristic를 활용해 아래와 같이 정의함.<br>

```swift
func makeService() -> CBMutableService {
    let transferService = CBMutableService(type: BLEUUID.serviceUUID, primary: true)
    transferService.characteristics = makeCharacteristics() // 특성 추가
    return transferService
}

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

    characteristics.transferCharacteristic = transferCharacteristic
    characteristics.nameCharacteristic = nameCharacteristic

    return [transferCharacteristic, nameCharacteristic]
}
```

- CBMutableService: Peripheral에서 제공할 서비스 정보를 정의. <br> 
- CBMutableCharacteristic: 데이터를 송수신하기 위한 특성을 정의.<br>
<br>
- .notify: Peripheral이 데이터 변경 시 Central로 알림(Notification)을 보냄.<br>
- .write: Central이 데이터를 전송할 수 있음. Peripheral은 응답 필요.<br>
- .writeWithoutResponse: Central이 데이터를 전송하지만 응답 불필요.<br>
- .read: Central이 데이터를 요청하여 Peripheral이 값을 반환함.<br>
<br><br>
2. Advertising 시작
정의된 서비스와 특성을 기반으로 Advertising을 시작함.

```swift
func startAdvertising() {
    guard manager.state == .poweredOn else { return }
    
    manager.add(makeService()) // 서비스 추가
    
    manager.startAdvertising([
        CBAdvertisementDataLocalNameKey: name.isEmpty ? "채팅을 원해요" : name,
        CBAdvertisementDataServiceUUIDsKey: [BLEUUID.serviceUUID]
    ])
}
```
- CBAdvertisementDataLocalNameKey: Advertising 시 Central에 표시될 이름을 설정.<br>
- Central에서 Advertising 데이터를 스캔<br>
- Central은 BLE Peripheral이 광고하는 데이터를 스캔하고 연결 가능한 기기를 탐색함.<br>
<br><br>
3. 스캔 시작
Central은 BLE 기능 활성화 후, **scanForPeripherals** 를 호출하여 데이터를 스캔함.<br>

```swift
private func startScanning() {
    guard manager.state == .poweredOn else { return }
    
    manager.scanForPeripherals(
        withServices: [BLEUUID.serviceUUID], // 특정 서비스 UUID만 스캔
        options: [CBCentralManagerScanOptionAllowDuplicatesKey: true] // 중복 스캔 허용
    )
    isScanning = true
}
```
- withServices: 스캔 대상의 서비스 UUID를 지정하여 특정 Peripheral을 필터링.<br>
- CBCentralManagerScanOptionAllowDuplicatesKey: 중복 Advertising 데이터도 스캔.<br>
<br><br>
4. Advertising 데이터 수신<br>
스캔 중 Peripheral을 발견하면 **centralManager(_:didDiscover:)**가 호출되어 데이터를 수신함.<br>

```swift
func centralManager(_ central: CBCentralManager,
                    didDiscover peripheral: CBPeripheral,
                    advertisementData: [String: Any],
                    rssi RSSI: NSNumber) {
    print("Discovered Peripheral: \(peripheral.name ?? "Unknown")")
    discoveredPeripherals.append(peripheral)
}
```
- RSSI: Peripheral의 신호 강도를 측정하여 물리적 거리나 신호 품질 평가에 활용.<br>
- Central에서 Peripheral 연결<br>
- Central은 스캔된 Peripheral을 선택하여 연결 요청을 진행함.<br>
<br><br><br>

### BLE 연결 과정: 연결
1. Peripheral 선택 및 연결 시도
```swift
func connect(to peripheral: CBPeripheral) {
    manager.stopScan() // 스캔 중단
    isScanning = false

    peripheral.delegate = self // Peripheral의 이벤트 처리를 위한 delegate 설정
    manager.connect(peripheral, options: nil) // Peripheral 연결 시도
}
```
- stopScan(): 연결 전 불필요한 스캔 중단.<br>
- manager.connect(): Peripheral에 연결 요청.<br>
<br>
2. 연결 성공 및 서비스 검색
연결 성공 시 **centralManager(_:didConnect:)**가 호출되어 서비스 검색을 시작함.

```swift
func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    print("Connected to: \(peripheral.name ?? peripheral.identifier.uuidString)")
    
    connectedPeripheral = peripheral
    isConnected = true
    
    peripheral.delegate = self // 이벤트 처리를 위한 delegate 설정
    peripheral.discoverServices(nil) // 모든 서비스 검색
}
```
- discoverServices(): Peripheral의 모든 서비스 또는 특정 서비스 UUID 검색.<br>
<br><br><br>
### BLE 데이터 교환 과정: GATT 규칙 활용
BLE 데이터 교환은 READ, WRITE, NOTIFY 방식으로 진행됨.<br>
<br><br>
1. READ: Central이 데이터를 요청하여 Peripheral에서 값을 반환
```swift
// Central에서 READ 요청
peripheral.readValue(for: characteristic)

// Peripheral에서 응답
func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
    request.value = name.data(using: .utf8)
    manager.respond(to: request, withResult: .success)
}

// Central이 READ 결과 처리
func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    guard let value = characteristic.value else { return }
    print("Read Value: \(String(data: value, encoding: .utf8) ?? "")")
}
```
<br><br>
2. WRITE: Central이 데이터를 전송하여 Peripheral에서 처리
```swift
// Central에서 WRITE 요청
connectedPeripheral?.writeValue(data, for: transferCharacteristic, type: .withResponse)

// Peripheral에서 WRITE 처리
func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
    for request in requests {
        guard let value = request.value else { continue }
        print("Received Data: \(String(data: value, encoding: .utf8) ?? "")")
    }
}
```
<br><br>
3. NOTIFY: Peripheral이 데이터 변경 시 Central로 알림
```swift
// Central에서 NOTIFY 활성화
peripheral.setNotifyValue(true, for: transferCharacteristic)

// Peripheral에서 알림 전송
manager.updateValue(data, for: transferCharacteristic, onSubscribedCentrals: nil)

// Central에서 알림 데이터 수신
func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    guard let value = characteristic.value else { return }
    print("Notified Value: \(String(data: value, encoding: .utf8) ?? "")")
}
```
<br><br>
#### 데이터 교환 방식 요약
READ: Central이 데이터를 요청하고, Peripheral이 값을 반환.<br>
WRITE: Central이 데이터를 전송하고, Peripheral이 이를 처리.<br>
NOTIFY: Peripheral이 값 변경 시 Central로 알림(Notification) 전송.<br>
