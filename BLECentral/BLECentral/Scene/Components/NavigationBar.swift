//
//  NavigationBar.swift
//  BLECentral
//
//  Created by 이재훈 on 11/11/24.
//

import SwiftUI

fileprivate struct NavigationBarModifier<LeftContent, CenterContent, RightContent>: ViewModifier where CenterContent: View, LeftContent: View, RightContent: View {
    let centerView: (() -> CenterContent)
    let leftView: (() -> LeftContent)
    let rightView: (() -> RightContent)
    
    init(
        centerView: @escaping (() -> CenterContent),
        leftView: @escaping (() -> LeftContent),
        rightView: @escaping (() -> RightContent)
    ) {
        self.centerView = centerView
        self.leftView = leftView
        self.rightView = rightView
    }
    
    func body(content: Content) -> some View {
        HStack(alignment: .center, spacing: 0) {
            Spacer()
                .frame(width: 16)
            self.leftView()
            Spacer()
            self.centerView()
            Spacer()
            self.rightView()
            Spacer()
                .frame(width: 16)
        }
        .frame(height: 48)
        .toolbar(.hidden)
    }
}

extension View {
    func displayNavigationBar<CenterContent, LeftContent, RightContent>(
        centerView: @escaping (() -> CenterContent),
        leftView: @escaping (() -> LeftContent),
        rightView: @escaping (() -> RightContent)
    ) -> some View where CenterContent: View, LeftContent: View, RightContent: View {
        modifier(
            NavigationBarModifier(centerView: centerView, leftView: leftView, rightView: rightView)
        )
    }
}
