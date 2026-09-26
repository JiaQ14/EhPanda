//
//  FavoritesReducer.swift
//  EhPanda
//

import SwiftUI
import IdentifiedCollections
import ComposableArchitecture

@Reducer
struct FavoritesReducer {
    private enum CancelID: Hashable {
        case request(Int)
    }

    @CasePathable
    enum Route: Equatable {
        case quickSearch(EquatableVoid = .init())
        case detail(String)
    }

    @ObservableState
    struct State: Equatable {
        var route: Route?
        var keyword = ""
        var submittedKeyword = ""
        var requestRevision = 0
        var activeRequests = [Int: Int]()

        var index = -1
        var sortOrder: FavoritesSortOrder?

        var rawGalleries = [Int: [Gallery]]()
        var rawPageNumber = [Int: PageNumber]()
        var rawLoadingState = [Int: LoadingState]()
        var rawFooterLoadingState = [Int: LoadingState]()

        var galleries: [Gallery]? {
            rawGalleries[index]
        }
        var pageNumber: PageNumber? {
            rawPageNumber[index]
        }
        var loadingState: LoadingState? {
            rawLoadingState[index]
        }
        var footerLoadingState: LoadingState? {
            rawFooterLoadingState[index]
        }

        var quickSearchState = QuickSearchReducer.State()

        mutating func insertGalleries(index: Int, galleries: [Gallery]) {
            rawGalleries[index, default: []].appendUniqueGalleries(galleries)
        }

        mutating func beginSearch(keyword: String?, sortOrder: FavoritesSortOrder?) -> Int {
            let query = (keyword ?? self.keyword).trimmingCharacters(in: .whitespacesAndNewlines)
            let order = sortOrder ?? self.sortOrder
            if query != submittedKeyword || order != self.sortOrder {
                rawGalleries.removeAll()
                rawPageNumber.removeAll()
                rawLoadingState.removeAll()
                rawFooterLoadingState.removeAll()
                activeRequests.removeAll()
            }
            self.keyword = query
            submittedKeyword = query
            self.sortOrder = order
            rawLoadingState[index] = .loading
            rawFooterLoadingState[index] = .idle
            rawPageNumber[index] = PageNumber()
            return beginRequest(index: index)
        }

        mutating func beginRequest(index: Int) -> Int {
            requestRevision += 1
            activeRequests[index] = requestRevision
            return requestRevision
        }

        func paginationRequest(index: Int) -> MoreFavoritesGalleriesRequest? {
            guard let pageNumber = rawPageNumber[index], pageNumber.hasNextPage(),
                  rawLoadingState[index] != .loading,
                  rawFooterLoadingState[index] != .loading,
                  let lastID = pageNumber.nextGalleryID ?? rawGalleries[index]?.last?.id,
                  let timestamp = pageNumber.lastItemTimestamp
            else { return nil }
            return MoreFavoritesGalleriesRequest(
                favIndex: index, lastID: lastID, lastTimestamp: timestamp, keyword: submittedKeyword
            )
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case setNavigation(Route?)
        case setFavoritesIndex(Int)
        case clearSubStates
        case onNotLoginViewButtonTapped

        case fetchGalleries(String? = nil, FavoritesSortOrder? = nil)
        case fetchGalleriesDone(Int, Int, Result<(PageNumber, FavoritesSortOrder?, [Gallery]), AppError>)
        case fetchMoreGalleries(Int? = nil)
        case fetchMoreGalleriesDone(Int, Int, Result<(PageNumber, FavoritesSortOrder?, [Gallery]), AppError>)

        case quickSearch(QuickSearchReducer.Action)
    }

    @Dependency(\.databaseClient) private var databaseClient
    @Dependency(\.hapticsClient) private var hapticsClient

    var body: some Reducer<State, Action> {
        BindingReducer()
            .onChange(of: \.route) { _, newValue in
                Reduce({ _, _ in newValue == nil ? .send(.clearSubStates) : .none })
            }
            .onChange(of: \.keyword) { oldValue, newValue in
                Reduce { _, _ in
                    guard !oldValue.isEmpty, newValue.isEmpty else { return .none }
                    return .send(.fetchGalleries())
                }
            }

        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .setNavigation(let route):
                state.route = route
                return route == nil ? .send(.clearSubStates) : .none

            case .setFavoritesIndex(let index):
                state.index = index
                guard state.galleries == nil, state.loadingState != .loading else { return .none }
                return .send(.fetchGalleries(state.submittedKeyword))

            case .clearSubStates:
                return .none

            case .onNotLoginViewButtonTapped:
                return .none

            case .fetchGalleries(let keyword, let sortOrder):
                let previousRequests = state.activeRequests.keys.map { $0 }
                let revision = state.beginSearch(keyword: keyword, sortOrder: sortOrder)
                let request = FavoritesGalleriesRequest(
                    favIndex: state.index, keyword: state.submittedKeyword, sortOrder: state.sortOrder
                )
                return .merge(
                    previousRequests.filter { state.activeRequests[$0] == nil }
                        .map { .cancel(id: CancelID.request($0)) }
                    + [.run { send in
                        let response = await request.response()
                        await send(.fetchGalleriesDone(request.favIndex, revision, response))
                    }.cancellable(id: CancelID.request(state.index), cancelInFlight: true)]
                )

            case .fetchGalleriesDone(let targetFavIndex, let revision, let result):
                guard state.activeRequests[targetFavIndex] == revision else { return .none }
                state.activeRequests[targetFavIndex] = nil
                state.rawLoadingState[targetFavIndex] = .idle
                switch result {
                case .success(let (pageNumber, sortOrder, galleries)):
                    // An empty response must replace the previous query's visible results too.
                    state.rawPageNumber[targetFavIndex] = pageNumber
                    state.rawGalleries[targetFavIndex] = galleries
                    state.sortOrder = sortOrder ?? state.sortOrder
                    guard !galleries.isEmpty else {
                        state.rawLoadingState[targetFavIndex] = .failed(.notFound)
                        guard pageNumber.hasNextPage(), pageNumber.nextGalleryID != nil else { return .none }
                        return .send(.fetchMoreGalleries(targetFavIndex))
                    }
                    return .run(operation: { _ in await databaseClient.cacheGalleries(galleries) })
                case .failure(let error):
                    state.rawLoadingState[targetFavIndex] = .failed(error)
                }
                return .none

            case .fetchMoreGalleries(let targetIndex):
                let index = targetIndex ?? state.index
                guard let request = state.paginationRequest(index: index) else { return .none }
                state.rawFooterLoadingState[index] = .loading
                let revision = state.beginRequest(index: index)
                return .run { send in
                    let response = await request.response()
                    await send(.fetchMoreGalleriesDone(index, revision, response))
                }
                .cancellable(id: CancelID.request(index), cancelInFlight: true)

            case .fetchMoreGalleriesDone(let targetFavIndex, let revision, let result):
                guard state.activeRequests[targetFavIndex] == revision else { return .none }
                state.activeRequests[targetFavIndex] = nil
                state.rawFooterLoadingState[targetFavIndex] = .idle
                switch result {
                case .success(let (pageNumber, sortOrder, galleries)):
                    let previousPage = state.rawPageNumber[targetFavIndex]
                    state.rawPageNumber[targetFavIndex] = pageNumber
                    state.insertGalleries(index: targetFavIndex, galleries: galleries)
                    state.sortOrder = sortOrder ?? state.sortOrder

                    var effects: [Effect<Action>] = [
                        .run(operation: { _ in await databaseClient.cacheGalleries(galleries) })
                    ]
                    if galleries.isEmpty, pageNumber.hasNextPage(), pageNumber != previousPage {
                        effects.append(.send(.fetchMoreGalleries(targetFavIndex)))
                    } else if galleries.isEmpty, pageNumber.hasNextPage() {
                        state.rawFooterLoadingState[targetFavIndex] = .failed(.parseFailed)
                    } else if !galleries.isEmpty {
                        state.rawLoadingState[targetFavIndex] = .idle
                    }
                    return .merge(effects)

                case .failure(let error):
                    state.rawFooterLoadingState[targetFavIndex] = .failed(error)
                }
                return .none

            case .quickSearch:
                return .none
            }
        }
        .haptics(
            unwrapping: \.route,
            case: \.quickSearch,
            hapticsClient: hapticsClient
        )

        Scope(state: \.quickSearchState, action: \.quickSearch, child: QuickSearchReducer.init)
    }
}
