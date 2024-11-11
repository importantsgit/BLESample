import SwiftUI
import CoreBluetooth
struct CentralView: View {
    @StateObject private var viewModel = BLECentralViewModel()
    @EnvironmentObject var navigationModel: NavigationModel

    var body: some View {
        VStack {
            displayNavigationBar {
                Text("CentralView")
            } leftView: {
                Button {
                    navigationModel.path.removeLast()
                } label: {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "chevron.backward")
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                            Spacer()
                        }
                        Spacer()
                    }
                }
                .frame(width: 48)
            } rightView: {
                Button {
                    viewModel.isConnected ? viewModel.cleanup() : viewModel.toggleScan()
                } label: {
                    Text(viewModel.isScanning ? "스캔 중지" : "스캔 시작")
                }
            }
            
            if viewModel.isConnected {
                Text("연결되었습니다.")
                Spacer()
            }
            else if viewModel.isScanning {
                ProgressView()
                    .progressViewStyle(.circular)
                Text("스캔 중...")
                List(viewModel.discoveredPeripherals, id: \.identifier) { peripheral in
                    HStack {
                        Button {
                            viewModel.connect(to: peripheral)
                        } label: {
                            VStack(alignment: .leading) {
                                VStack(alignment: .leading) {
                                    Text(peripheral.name ?? "Unknown Device")
                                        .font(.headline)
                                    Text(peripheral.identifier.uuidString)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                if let rssi = viewModel.peripheralRSSIs[peripheral.identifier] {
                                    HStack {
                                        Text("\(rssi) dBm")
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            else {
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Peripheral에 알릴 Name을 입력 후, 스캔을 진행해주세요.")
                        .font(.subheadline)
                    TextField("Name 입력", text: $viewModel.name)
                        .textFieldStyle(.roundedBorder)
                }
                .padding()
                Spacer()
            }
        }
        .onAppear {
            viewModel.onAppear()
        }
        .fullScreenCover(isPresented: $viewModel.isConnected) {
            ChatView(viewModel: viewModel)
        }
    }
}
