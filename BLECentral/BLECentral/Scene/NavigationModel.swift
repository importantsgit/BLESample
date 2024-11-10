//
//  NavigationModel.swift
//  BLECentral
//
//  Created by 이재훈 on 11/11/24.
//

import SwiftUI
import Combine

enum Screen: Hashable {
    case central
    case peripheral
}

final class NavigationModel: ObservableObject {
    @Published var path: [Screen] = []
}

