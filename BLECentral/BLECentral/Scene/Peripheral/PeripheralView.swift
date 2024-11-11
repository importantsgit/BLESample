//
//  PeripheralView.swift
//  BLECentral
//
//  Created by 이재훈 on 11/7/24.
//
//
//  PeripheralView.swift
//  BLECentral
//
//  Created by 이재훈 on 11/7/24.
//

import CoreBluetooth
import SwiftUI

struct PeripheralView: View {
    @StateObject var viewModel = PeripheralViewModel()
    @EnvironmentObject var navigationModel: NavigationModel
    
    var body: some View {
        VStack {
            displayNavigationBar {
                Text("PeripheralView")
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
                Button(viewModel.isAdvertising ? "광고 중지" : "광고 시작") {
                    viewModel.toogleAdvertising()
                }
            }
            
            if viewModel.isAdvertising {
                Spacer()
                ProgressView {
                    Text("연결할 Central을 찾고 있습니다.")
                }
                .progressViewStyle(.circular)
                .font(.headline)
                Spacer()
            }
            else if viewModel.connectedCentral != nil {
                Spacer()
                Text("연결할 Central을 찾았습니다.")
                Spacer()
            }
            else {
                Spacer()
                Text("광고를 시작해주세요.")
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
