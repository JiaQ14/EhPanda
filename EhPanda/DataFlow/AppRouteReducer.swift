//
//  AppRouteReducer.swift
//  EhPanda
//

import SwiftUI
import TTProgressHUD
import ComposableArchitecture

@Reducer
struct AppRouteReducer {
    private enum CancelOperation: CaseIterable {
        case deferredNavigation
        case fetchGallery
    }

    private typealias CancelID = ReducerCancellationID<CancelOperation>

    @CasePathable
    enum Route: Equatable, Hashable {
        case hud
        case setting(EquatableVoid = .init())
        case detail(String)
        case newDawn(Greeting)
    }

    @ObservableState
    struct State: Equatable {
        var cancellationScope = UUID()
        var route: Route?
        var hudConfig: TTProgressHUDConfig = .loading

        var detailState: Heap<DetailReducer.State?>

        init() {
            detailState = .init(.init())
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case setNavigation(Route?)
        case setHUDConfig(TTProgressHUDConfig)
        case clearSubStates
        case resetDetailState

        case detectClipboardURL
        case handleDeepLink(URL)
        case handleGalleryLink(URL)
        case presentGalleryLink(URL)
        case openGallery(String, Int?)
        case presentGallery(String, Int?)

        case updateReadingProgress(String, Int)

        case fetchGallery(URL, Bool)
        case fetchGalleryDone(URL, Result<Gallery, AppError>)
        case fetchGreetingDone(Result<Greeting, AppError>)

        case detail(DetailReducer.Action)
    }

    @Dependency(\.userDefaultsClient) private var userDefaultsClient
    @Dependency(\.clipboardClient) private var clipboardClient
    @Dependency(\.databaseClient) private var databaseClient
    @Dependency(\.hapticsClient) private var hapticsClient
    @Dependency(\.urlClient) private var urlClient

    var body: some Reducer<State, Action> {
        BindingReducer()
            .onChange(of: \.route) { _, newValue in
                Reduce({ _, _ in newValue == nil ? .send(.clearSubStates) : .none })
            }

        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .setNavigation(let route):
                if case .hud = route {
                    state.hudConfig = .loading
                }
                state.route = route
                return route == nil ? .send(.clearSubStates) : .none

            case .setHUDConfig(let config):
                state.hudConfig = config
                return .none

            case .clearSubStates:
                return .concatenate(
                    .merge(
                        CancelOperation.allCases.map {
                            Effect.cancel(id: cancelID($0, state: state))
                        }
                    ),
                    .send(.detail(.teardown)),
                    .send(.resetDetailState)
                )

            case .resetDetailState:
                state.detailState.wrappedValue = .init()
                return .none

            case .detectClipboardURL:
                let currentChangeCount = clipboardClient.changeCount()
                guard currentChangeCount != userDefaultsClient
                        .getValue(.clipboardChangeCount) else { return .none }
                var effects: [Effect<Action>] = [
                    .run(operation: { _ in userDefaultsClient.setValue(currentChangeCount, .clipboardChangeCount) })
                ]
                if let url = clipboardClient.url() {
                    effects.append(.send(.handleDeepLink(url)))
                }
                return .merge(effects)

            case .handleDeepLink(let url):
                let url = urlClient.resolveAppSchemeURL(url) ?? url
                guard urlClient.checkIfHandleable(url) else { return .none }
                var delay = 0
                var clearsCurrentDetail = false
                if case .detail = state.route {
                    delay = 1000
                    state.route = nil
                    clearsCurrentDetail = true
                }
                let (isGalleryImageURL, _, _) = urlClient.analyzeURL(url)
                let gid = urlClient.parseGalleryID(url)
                let nextEffect: Effect<Action>
                guard databaseClient.fetchGallery(gid: gid) == nil else {
                    nextEffect = .run { [delay] send in
                        try await Task.sleep(for: .milliseconds(delay + 250))
                        await send(.handleGalleryLink(url))
                    }
                    .cancellable(
                        id: cancelID(.deferredNavigation, state: state),
                        cancelInFlight: true
                    )
                    return clearsCurrentDetail
                        ? .concatenate(.send(.clearSubStates), nextEffect)
                        : nextEffect
                }
                nextEffect = .run { [delay] send in
                    try await Task.sleep(for: .milliseconds(delay))
                    await send(.fetchGallery(url, isGalleryImageURL))
                }
                .cancellable(
                    id: cancelID(.deferredNavigation, state: state),
                    cancelInFlight: true
                )
                return clearsCurrentDetail
                    ? .concatenate(.send(.clearSubStates), nextEffect)
                    : nextEffect

            case .handleGalleryLink(let url):
                let (_, pageIndex, commentID) = urlClient.analyzeURL(url)
                let gid = urlClient.parseGalleryID(url)
                if pageIndex != nil || commentID == nil {
                    return .send(.openGallery(gid, pageIndex))
                }
                return .concatenate(
                    .cancel(id: cancelID(.deferredNavigation, state: state)),
                    .send(.detail(.teardown)),
                    .send(.presentGalleryLink(url))
                )

            case .presentGalleryLink(let url):
                let (_, _, commentID) = urlClient.analyzeURL(url)
                let gid = urlClient.parseGalleryID(url)
                var effects = [Effect<Action>]()
                state.detailState.wrappedValue = .init()
                effects.append(.send(.detail(.fetchDatabaseInfos(gid))))
                if let commentID = commentID {
                    state.detailState.wrappedValue?.commentsState.wrappedValue = .init()
                    state.detailState.wrappedValue?.commentsState.wrappedValue?.scrollCommentID = commentID
                    effects.append(
                        .run { send in
                            try await Task.sleep(for: .milliseconds(500))
                            await send(.detail(.setNavigation(.comments(url))))
                        }
                        .cancellable(
                            id: cancelID(.deferredNavigation, state: state),
                            cancelInFlight: true
                        )
                    )
                }
                effects.append(.send(.setNavigation(.detail(gid))))
                return .merge(effects)

            case .openGallery(let gid, let readingProgress):
                guard gid.isValidGID else { return .none }
                return .concatenate(
                    .cancel(id: cancelID(.deferredNavigation, state: state)),
                    .send(.detail(.teardown)),
                    .send(.presentGallery(gid, readingProgress))
                )

            case .presentGallery(let gid, let readingProgress):
                state.detailState.wrappedValue = .init()
                var effects: [Effect<Action>] = [
                    .send(.detail(.fetchDatabaseInfos(gid))),
                    .send(.setNavigation(.detail(gid)))
                ]
                if let readingProgress {
                    effects.append(.send(.updateReadingProgress(gid, readingProgress)))
                    effects.append(
                        .run { send in
                            try await Task.sleep(for: .milliseconds(500))
                            await send(.detail(.setNavigation(.reading())))
                        }
                        .cancellable(
                            id: cancelID(.deferredNavigation, state: state),
                            cancelInFlight: true
                        )
                    )
                }
                return .merge(effects)

            case .updateReadingProgress(let gid, let progress):
                guard !gid.isEmpty else { return .none }
                return .run { _ in
                    await databaseClient.updateReadingProgress(gid: gid, progress: progress)
                }

            case .fetchGallery(let url, let isGalleryImageURL):
                state.hudConfig = .loading
                state.route = .hud
                return .run { send in
                    let response = await GalleryReverseRequest(
                        url: url, isGalleryImageURL: isGalleryImageURL
                    )
                    .response()
                    await send(.fetchGalleryDone(url, response))
                }
                .cancellable(
                    id: cancelID(.fetchGallery, state: state),
                    cancelInFlight: true
                )

            case .fetchGalleryDone(let url, let result):
                switch result {
                case .success(let gallery):
                    state.route = nil
                    return .merge(
                        .run(operation: { _ in await databaseClient.cacheGalleries([gallery]) }),
                        .send(.handleGalleryLink(url))
                    )
                case .failure:
                    state.hudConfig = .error
                    return .none
                }

            case .fetchGreetingDone(let result):
                if case .success(let greeting) = result, !greeting.gainedNothing {
                    return .send(.setNavigation(.newDawn(greeting)))
                }
                return .none

            case .detail:
                return .none
            }
        }
        .haptics(
            unwrapping: \.route,
            case: \.newDawn,
            hapticsClient: hapticsClient
        )
        .haptics(
            unwrapping: \.route,
            case: \.detail,
            hapticsClient: hapticsClient
        )

        Scope(state: \.detailState.wrappedValue!, action: \.detail, child: DetailReducer.init)
    }

    private func cancelID(_ operation: CancelOperation, state: State) -> CancelID {
        CancelID(scope: state.cancellationScope, operation: operation)
    }
}
