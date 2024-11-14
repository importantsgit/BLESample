//
//  ChatViewModel.swift
//  BLECentral
//
//  Created by 이재훈 on 11/11/24.
//

import Foundation

protocol ChatViewModel: AnyObject, ObservableObject {
    var text: String { get set }
    var name: String { get set }
    var userName: String { get set }
    var textPublisher: Published<String>.Publisher { get }
    var chats: [Chat] { get set }
    var isConnected: Bool { get set }
    
    func cleanup()
    func sendButtonTapped()
}
