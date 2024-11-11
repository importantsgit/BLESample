//
//  ContentView.swift
//  BLECentral
//
//  Created by 이재훈 on 11/7/24.
//

import CoreBluetooth
import SwiftUI



enum BLEUUID {
    static let serviceUUID = CBUUID(string: "12340987-1111-3333-5555-875612543926")
    static let transferCharacteristicUUID = CBUUID(string: "08590F7E-DB05-467E-8757-72F6FAEB13D4")
    static let nameCharacteristicUUID = CBUUID(string: "08590F7E-DB05-467E-8757-72F6FAEB13D5")
}

struct ContentView: View {
    @StateObject var navigationModel: NavigationModel = NavigationModel()
    var body: some View {
        NavigationStack(path: $navigationModel.path) {
            List {
                Button("Central") {navigationModel.path.append(.central)}
                Button("Peripheral") {navigationModel.path.append(.peripheral)}
            }
            .navigationDestination(for: Screen.self) { screen in
                Group {
                    switch screen {
                    case .central:
                        CentralView()
                    case .peripheral:
                        PeripheralView()
                    }
                }
                .environmentObject(navigationModel)
            }
        }
    }
}
