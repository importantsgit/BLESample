//
//  DetailView.swift
//  BLECentral
//
//  Created by 이재훈 on 11/7/24.
//

import SwiftUI

struct DetailView: View {
    @ObservedObject var viewModel: BLECentralViewModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .trailing){
                ForEach(viewModel.chats) { chat in
                    Button{
                        
                    } label: {
                        Text(chat.content)
                            .padding()
                            .font(.system(size: 14, weight: .medium))
                            .background(.yellow)
                            .clipShape(.rect(cornerRadius: 4))
                    }
                }
            }
            .padding()
        }

    }
}
