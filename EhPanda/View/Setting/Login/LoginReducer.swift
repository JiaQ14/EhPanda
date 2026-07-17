//
//  LoginReducer.swift
//  EhPanda
//

import ComposableArchitecture

@Reducer
struct LoginReducer {
    @ObservableState
    struct State: Equatable {}

    enum Action: Equatable {
        case loginDone
    }

    @Dependency(\.hapticsClient) private var hapticsClient

    var body: some Reducer<State, Action> {
        Reduce { _, _ in
            .run(operation: { _ in hapticsClient.generateNotificationFeedback(.success) })
        }
    }
}
