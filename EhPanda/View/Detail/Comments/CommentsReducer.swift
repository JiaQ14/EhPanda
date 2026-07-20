//
//  CommentsReducer.swift
//  EhPanda
//

import Foundation
import TTProgressHUD
import ComposableArchitecture

@Reducer
struct CommentsReducer {
    @CasePathable
    enum Route: Equatable {
        case hud
        case detail(String)
        case postComment(String)
    }

    private enum CancelOperation: CaseIterable {
        case postComment, voteComment, fetchGallery
        case deferredNavigation, scrollPresentation, postCommentFocus
    }

    private typealias CancelID = ReducerCancellationID<CancelOperation>

    @ObservableState
    struct State: Equatable {
        var cancellationScope = UUID()
        var route: Route?
        var commentContent = ""
        var postCommentFocused = false

        var hudConfig: TTProgressHUDConfig = .loading
        var scrollCommentID: String?
        var scrollRowOpacity: Double = 1

        var detailState: Heap<DetailReducer.State?>

        init() {
            detailState = .init(.init())
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case setNavigation(Route?)
        case clearSubStates
        case resetSubStates
        case clearScrollCommentID

        case setHUDConfig(TTProgressHUDConfig)
        case setPostCommentFocused(Bool)
        case setScrollRowOpacity(Double)
        case setCommentContent(String)
        case performScrollOpacityEffect
        case handleCommentLink(URL)
        case handleGalleryLink(URL)
        case presentGalleryLink(URL)
        case onPostCommentAppear
        case onAppear

        case updateReadingProgress(String, Int)

        case teardown
        case postComment(URL, String? = nil)
        case voteComment(String, String, String, String, Int)
        case performCommentActionDone(Result<Any, AppError>)
        case fetchGallery(URL, Bool)
        case fetchGalleryDone(URL, Result<Gallery, AppError>)

        case detail(DetailReducer.Action)
    }

    @Dependency(\.uiApplicationClient) private var uiApplicationClient
    @Dependency(\.databaseClient) private var databaseClient
    @Dependency(\.hapticsClient) private var hapticsClient
    @Dependency(\.cookieClient) private var cookieClient
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
                state.route = route
                return route == nil ? .send(.clearSubStates) : .none

            case .clearSubStates:
                return .concatenate(
                    .merge(
                        .cancel(id: cancelID(.deferredNavigation, state: state)),
                        .cancel(id: cancelID(.scrollPresentation, state: state)),
                        .cancel(id: cancelID(.postCommentFocus, state: state))
                    ),
                    .send(.detail(.teardown)),
                    .send(.resetSubStates)
                )

            case .resetSubStates:
                state.detailState.wrappedValue = .init()
                state.commentContent = .init()
                state.postCommentFocused = false
                return .none

            case .clearScrollCommentID:
                state.scrollCommentID = nil
                return .none

            case .setHUDConfig(let config):
                state.hudConfig = config
                return .none

            case .setPostCommentFocused(let isFocused):
                state.postCommentFocused = isFocused
                return .none

            case .setScrollRowOpacity(let opacity):
                state.scrollRowOpacity = opacity
                return .none

            case .setCommentContent(let content):
                state.commentContent = content
                return .none

            case .performScrollOpacityEffect:
                return .merge(
                    .run { send in
                        try await Task.sleep(for: .milliseconds(750))
                        await send(.setScrollRowOpacity(0.25))
                    },
                    .run { send in
                        try await Task.sleep(for: .milliseconds(1250))
                        await send(.setScrollRowOpacity(1))
                    },
                    .run { send in
                        try await Task.sleep(for: .milliseconds(2000))
                        await send(.clearScrollCommentID)
                    }
                )
                .cancellable(
                    id: cancelID(.scrollPresentation, state: state),
                    cancelInFlight: true
                )

            case .handleCommentLink(let url):
                guard urlClient.checkIfHandleable(url) else {
                    return .run(operation: { _ in await uiApplicationClient.openURL(url) })
                }
                let (isGalleryImageURL, _, _) = urlClient.analyzeURL(url)
                let gid = urlClient.parseGalleryID(url)
                guard databaseClient.fetchGallery(gid: gid) == nil else {
                    return .send(.handleGalleryLink(url))
                }
                return .send(.fetchGallery(url, isGalleryImageURL))

            case .handleGalleryLink(let url):
                return .concatenate(
                    .cancel(id: cancelID(.deferredNavigation, state: state)),
                    .send(.detail(.teardown)),
                    .send(.presentGalleryLink(url))
                )

            case .presentGalleryLink(let url):
                let (_, pageIndex, commentID) = urlClient.analyzeURL(url)
                let gid = urlClient.parseGalleryID(url)
                state.detailState.wrappedValue = .init()
                var effects = [Effect<Action>]()
                if let pageIndex = pageIndex {
                    effects.append(.send(.updateReadingProgress(gid, pageIndex)))
                    effects.append(
                        .run { send in
                            try await Task.sleep(for: .milliseconds(750))
                            await send(.detail(.setNavigation(.reading())))
                        }
                        .cancellable(
                            id: cancelID(.deferredNavigation, state: state),
                            cancelInFlight: true
                        )
                    )
                } else if let commentID = commentID {
                    state.detailState.wrappedValue?.commentsState.wrappedValue = .init()
                    state.detailState.wrappedValue?.commentsState.wrappedValue?.scrollCommentID = commentID
                    effects.append(
                        .run { send in
                            try await Task.sleep(for: .milliseconds(750))
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

            case .onPostCommentAppear:
                return .run { send in
                    try await Task.sleep(for: .milliseconds(750))
                    await send(.setPostCommentFocused(true))
                }
                .cancellable(
                    id: cancelID(.postCommentFocus, state: state),
                    cancelInFlight: true
                )

            case .onAppear:
                if state.detailState.wrappedValue == nil {
                    state.detailState.wrappedValue = .init()
                }
                return state.scrollCommentID != nil ? .send(.performScrollOpacityEffect) : .none

            case .updateReadingProgress(let gid, let progress):
                guard !gid.isEmpty else { return .none }
                return .run { _ in
                    await databaseClient.updateReadingProgress(gid: gid, progress: progress)
                }

            case .teardown:
                var effects = CancelOperation.allCases.map {
                    Effect<Action>.cancel(id: cancelID($0, state: state))
                }
                if state.detailState.wrappedValue != nil {
                    effects.append(.send(.detail(.teardown)))
                }
                return .merge(effects)

            case .postComment(let galleryURL, let commentID):
                guard !state.commentContent.isEmpty else { return .none }
                if let commentID = commentID {
                    return .run { [commentContent = state.commentContent] send in
                        let response = await EditGalleryCommentRequest(
                            commentID: commentID,
                            content: commentContent,
                            galleryURL: galleryURL
                        )
                        .response()
                        await send(.performCommentActionDone(response))
                    }
                    .cancellable(id: cancelID(.postComment, state: state))
                } else {
                    return .run { [commentContent = state.commentContent] send in
                        let response = await CommentGalleryRequest(
                            content: commentContent, galleryURL: galleryURL
                        )
                        .response()
                        await send(.performCommentActionDone(response))
                    }
                    .cancellable(id: cancelID(.postComment, state: state))
                }

            case .voteComment(let gid, let token, let apiKey, let commentID, let vote):
                guard let gid = Int(gid), let commentID = Int(commentID),
                      let apiuid = Int(cookieClient.apiuid)
                else { return .none }
                return .run {  send in
                    let response = await VoteGalleryCommentRequest(
                        apiuid: apiuid,
                        apikey: apiKey,
                        gid: gid,
                        token: token,
                        commentID: commentID,
                        commentVote: vote
                    )
                    .response()
                    await send(.performCommentActionDone(response))
                }
                .cancellable(id: cancelID(.voteComment, state: state))

            case .performCommentActionDone:
                return .none

            case .fetchGallery(let url, let isGalleryImageURL):
                state.hudConfig = .loading
                state.route = .hud
                return .run {  send in
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

            case .detail:
                return .none
            }
        }
        .haptics(
            unwrapping: \.route,
            case: \.postComment,
            hapticsClient: hapticsClient
        )
    }

    private func cancelID(_ operation: CancelOperation, state: State) -> CancelID {
        CancelID(scope: state.cancellationScope, operation: operation)
    }
}
