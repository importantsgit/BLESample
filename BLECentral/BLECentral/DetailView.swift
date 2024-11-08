//
//  DetailView.swift
//  BLECentral
//
//  Created by 이재훈 on 11/7/24.
//

import SwiftUI

struct DetailView: View {
    @ObservedObject var viewModel: BLECentralViewModel
    @State private var message: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // 네비게이션
            
            VStack(spacing: 10) {
                ScrollView(.vertical, showsIndicators: false) {
                    
                    ScrollViewReader { reader in
                        LazyVStack(spacing: 20) {
                            if #available(iOS 17.0, *) {
                                ForEach(viewModel.chats) { chat in
                                    ChatBubble(chat: chat)
                                }
                                .onChange(of: viewModel.chats) { _, newValue in
                                    reader.scrollTo(newValue.last?.id)
                                }
                            } else {
                                ForEach(viewModel.chats) { chat in
                                    ChatBubble(chat: chat)
                                }
                                .onChange(of: viewModel.chats) { newValue in
                                    // FIXME: 채팅 스크롤 bottom에 맞추기
                                    reader.scrollTo(newValue.last?.id, anchor: .bottom)
                                }
                            }
                        }
                        .padding([.horizontal,.bottom])
                        .padding(.top, 25)
                    }
                }
                HStack(spacing: 15) {
                    HStack(spacing: 15) {
                        TextField("Message", text: $message)
                        Button{
                        } label: {
                            Image(systemName: "paperclip.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal)
                    .background(Color.black.opacity(0.06))
                    .clipShape(Capsule())
                    
                    if message != "" {
                        Button {
                            withAnimation(.easeIn){
                                viewModel.chats.append(.init(myChat: true, content: message))
                                // TODO: - 해당 메세지 입력 시의 처리 -> Peripheral에 던져야 함
                            }
                            message = ""
                        } label: {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 22))
                                .foregroundColor(Color.blue) // TODO: 배경색 바꾸기
                                .rotationEffect(.init(degrees: 45))
                                .padding(.vertical,12)
                                .padding(.leading,12)
                                .padding(.trailing,17)
                                .background(Color.black.opacity(0.07))
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.horizontal)
                .animation(.easeOut, value: message)
            }
            // FIXME: 해당 window 값 바꾸기
            .padding(.bottom, UIApplication.shared.windows.first?.safeAreaInsets.bottom)
            .background(Color.white.clipShape(RoundedShape()))
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .background(Color.blue.edgesIgnoringSafeArea(.top)) // TODO: 배경색 맞추기
    }
}

struct ChatBubble: View {
    var chat: Chat
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if chat.myChat {
                Spacer(minLength: 25)
                
                Text(chat.content)
                    .padding(.all)
                    .background(Color.black.opacity(0.06))
                    .clipShape(BubbleArrow(myMsg: chat.myChat))
                
                Circle()
                    .fill(Color.red)
                    .frame(width: 30, height: 30)
            }
            else {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 30, height: 30)
                
                Text(chat.content)
                    .padding(.all)
                    .foregroundColor(.white)
                    .background(Color.blue) // TODO: 배경색 맞추기
                    .clipShape(BubbleArrow(myMsg: chat.myChat))
                
                Spacer(minLength: 25)
            }
        }
        .id(chat.id)
    }
}

struct BubbleArrow : Shape {
    var myMsg : Bool
    func path(in rect: CGRect) -> Path {
        
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: myMsg ?  [.topLeft,.bottomLeft,.bottomRight] : [.topRight,.bottomLeft,.bottomRight], cornerRadii: CGSize(width: 10, height: 10))
        
        return Path(path.cgPath)
    }
}

struct RoundedShape : Shape {
    
    func path(in rect: CGRect) -> Path {
        
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: [.topLeft,.topRight], cornerRadii: CGSize(width: 35, height: 35))
        
        return Path(path.cgPath)
    }
}
