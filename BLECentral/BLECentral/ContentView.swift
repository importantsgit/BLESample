//
//  ContentView.swift
//  BLECentral
//
//  Created by 이재훈 on 11/7/24.
//

import CoreBluetooth
import SwiftUI

enum Screen: Hashable {
    case central
    case peripheral
}

enum BLEUUID {
    static let serviceUUID = CBUUID(string: "12340987-1111-3333-5555-875612543926")
    static let characteristicUUID = CBUUID(string: "08590F7E-DB05-467E-8757-72F6FAEB13D4")
}

struct ContentView: View {
    @State private var path: [Screen] = []
    var body: some View {
        NavigationStack(path: $path) {
            List {
                Button("Central") {path.append(.central)}
                Button("Peripheral") {path.append(.peripheral)}
            }
            .navigationDestination(for: Screen.self) { screen in
                switch screen {
                case .central:
                    CentralView()
                case .peripheral:
                    PeripheralView()
                }
            }
        }
    }
}
