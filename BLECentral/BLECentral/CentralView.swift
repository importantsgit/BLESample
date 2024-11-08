import SwiftUI
import CoreBluetooth
struct CentralView: View {
    @StateObject private var viewModel = BLECentralViewModel()
    
    var body: some View {
        VStack {
            if viewModel.isScanning {
                ProgressView()
                    .progressViewStyle(.circular)
                Text("스캔 중...")
            }
            
            if viewModel.isConnected {
                DetailView(viewModel: viewModel)
            }
            else {
                List(Array(viewModel.discoveredPeripherals.enumerated()), id: \.1.identifier) { index, peripheral in
                    HStack {
                        Button {
                            viewModel.connect(to: peripheral)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(peripheral.name ?? "Unknown Device")
                                    .font(.headline)
                                Text(peripheral.identifier.uuidString)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            if let rssi = viewModel.peripheralRSSIs[peripheral.identifier] {
                                Text("\(rssi) dBm")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Central")
        .toolbar {
            if viewModel.isConnected {
                Button("연결 해제") {
                    viewModel.cleanup()
                }
            }
            else {
                Button(viewModel.isScanning ? "스캔 중지" : "스캔 시작") {
                    viewModel.toggleScan()
                }
            }
        }
    }
}

class BLECentralViewModel: NSObject, ObservableObject {
    @Published var discoveredPeripherals: [CBPeripheral] = []
    @Published var isScanning = false
    @Published var isConnected = false
    @Published var chats: [Chat] = []
    var updateText = ""
    private var connectedPeripheral: CBPeripheral? = nil
    
    var peripheralRSSIs: [UUID: NSNumber] = [:]
    private lazy var manager: CBCentralManager = {
        let options: [String: Any] = [
            CBCentralManagerOptionShowPowerAlertKey: true
            // true인 경우, Manager가 scanForPeripherals 할 때 블투투스가 꺼진 상태라면 Alert을 띄움
            // 만약 커스텀 Alert을 띄우고 싶다면 해당 key <= false
        ]
        return CBCentralManager(delegate: self, queue: .global(), options: options)
    }()
    
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
                if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
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
            peripheral.discoverCharacteristics([BLEUUID.characteristicUUID], for: service)
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
                peripheral.setNotifyValue(true, for: characteristic)
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
        
        if stringFromData == "EOM" {
            Task { @MainActor in
                chats.append(.init(
                    myChat: false,
                    content: updateText
                ))
                updateText = ""
            }
        }
        else {
            updateText += stringFromData
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
