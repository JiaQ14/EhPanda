//
//  LoginView.swift
//  EhPanda
//

import SwiftUI
import ComposableArchitecture

struct LoginView: View {
    private let store: StoreOf<LoginReducer>

    init(store: StoreOf<LoginReducer>) {
        self.store = store
    }

    var body: some View {
        WebView(url: Defaults.URL.webLogin) {
            store.send(.loginDone)
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(L10n.Localizable.LoginView.Title.login)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            LoginView(
                store: .init(initialState: .init(), reducer: LoginReducer.init)
            )
        }
    }
}
