//
//  ChatView.swift
//  BLECentral
//
//  Created by 이재훈 on 11/7/24.
//

import SwiftUI

struct ChatView<ViewModel: ChatViewModel>: View {
    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject var navigationModel: NavigationModel
    
    var body: some View {
        VStack(spacing: 0) {
            displayNavigationBar {
                Text("ChatView")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            } leftView: {
                Button {
                    viewModel.cleanup()
                } label: {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "chevron.backward")
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                                .tint(.white)
                            Spacer()
                        }
                        Spacer()
                    }
                }
                .frame(width: 48)
            } rightView: {
                Spacer()
                    .frame(width: 48)
            }

            VStack(spacing: 10) {
                ScrollView(.vertical, showsIndicators: false) {
                    
                    ScrollViewReader { reader in
                        LazyVStack(spacing: 16) {
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
                        TextField("Message", text: $viewModel.text)
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
                    
                    if viewModel.text != "" {
                        Button {
                            withAnimation(.easeIn){
                                viewModel.sendButtonTapped()
                            }
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
                .animation(.easeOut, value: viewModel.text)
            }
            // FIXME: 해당 window 값 바꾸기
            .padding(.bottom, UIApplication.shared.windows.first?.safeAreaInsets.bottom)
            .background(Color.white.clipShape(RoundedShape()))
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .background(Color.blue.edgesIgnoringSafeArea(.top))
        .onReceive(viewModel.textPublisher) { _ in
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
    }
}

struct ChatBubble: View {
    var chat: Chat
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if chat.myChat {
                Spacer(minLength: 25)
                
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: 20)
                    Text(chat.content)
                        .padding(.all)
                        .foregroundStyle(.white)
                        .font(.system(size: 16, weight: .medium))
                        .background(Color.blue.opacity(0.9))
                        .clipShape(BubbleArrow(myMsg: chat.myChat))
                }
            }
            else {
                let userName = chat.userName != nil ?
                (chat.userName!.isEmpty ? "B" : chat.userName!) :
                "B"
                ZStack(alignment: .center) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 40, height: 40)
                    
                    Text(userName.prefix(1))
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .bold))
                }
                
                VStack {
                    Spacer()
                        .frame(height: 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(userName)
                            .font(.system(size: 14, weight: .light))
                        Text(chat.content)
                            .padding(.all)
                            .foregroundColor(.black)
                            .font(.system(size: 16, weight: .medium))
                            .background(Color.blue.opacity(0.2)) // TODO: 배경색 맞추기
                            .clipShape(BubbleArrow(myMsg: chat.myChat))
                    }
                }
                Spacer(minLength: 25)
            }
        }
        .id(chat.id)
    }
}

struct BubbleArrow : Shape {
    var myMsg : Bool
    func path(in rect: CGRect) -> Path {
        
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: myMsg ?  [.topLeft,.bottomLeft,.bottomRight] : [.topRight,.bottomLeft,.bottomRight], cornerRadii: CGSize(width: 16, height: 16))
        
        return Path(path.cgPath)
    }
}

struct RoundedShape : Shape {
    
    func path(in rect: CGRect) -> Path {
        
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: [.topLeft,.topRight], cornerRadii: CGSize(width: 35, height: 35))
        
        return Path(path.cgPath)
    }
}

@available(iOS 17.0, *)
#Preview {
    ChatBubble(chat: .init(myChat: true, content: "Hello"))
    ChatBubble(chat: .init(myChat: false, userName: "Jaehun", content: "Hello"))
    ChatBubble(chat: .init(myChat: false, userName: "재훈", content: "Hello"))
}
