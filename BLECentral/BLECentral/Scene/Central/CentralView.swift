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
            
            if viewModel.isScanning {
                ProgressView()
                    .progressViewStyle(.circular)
                Text("스캔 중...")
            }
            
            if viewModel.isConnected {
                Text("연결되었습니다.")
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
        .fullScreenCover(isPresented: $viewModel.isConnected) {
            DetailView(viewModel: viewModel)
        }
        .navigationTitle("Central")
        .onAppear {
            viewModel.onAppear()
        }
    }
}
