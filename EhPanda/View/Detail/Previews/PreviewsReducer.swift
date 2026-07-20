//
//  PreviewsReducer.swift
//  EhPanda
//

import Foundation
import ComposableArchitecture

@Reducer
struct PreviewsReducer {
    @CasePathable
    enum Route: Equatable {
        case reading(EquatableVoid = .init())
    }

    private enum CancelOperation: CaseIterable {
        case fetchDatabaseInfos, fetchPreviewURLs
    }

    private typealias CancelID = ReducerCancellationID<CancelOperation>

    @ObservableState
    struct State: Equatable {
        var cancellationScope = UUID()
        var route: Route?

        var gallery: Gallery = .empty
        var loadingState: LoadingState = .idle
        var databaseLoadingState: LoadingState = .loading

        var previewURLs = [Int: URL]()
        var previewConfig: PreviewConfig = .normal(rows: 4)
        var loadingPages = Set<Int>()
        var pendingPreviewIndices = Set<Int>()
        var pageErrors = [Int: AppError]()
        var automaticallyRetriedPages = Set<Int>()

        var readingState = ReadingReducer.State()

        mutating func updatePreviewURLs(_ previewURLs: [Int: URL]) {
            self.previewURLs.merge(previewURLs, uniquingKeysWith: { _, new in new })
        }

        mutating func updateLoadingState() {
            if !loadingPages.isEmpty {
                loadingState = .loading
            } else if let error = pageErrors.sorted(by: { $0.key < $1.key }).first?.value {
                loadingState = .failed(error)
            } else {
                loadingState = .idle
            }
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case setNavigation(Route?)
        case clearSubStates
        case resetSubStates

        case syncPreviewURLs([Int: URL])
        case updateReadingProgress(Int)

        case teardown
        case fetchDatabaseInfos(String)
        case fetchDatabaseInfosDone(GalleryPreviewCache?)
        case fetchPreviewURLs(Int)
        case fetchPreviewURLsDone(Int, Result<[Int: URL], AppError>)

        case reading(ReadingReducer.Action)
    }

    @Dependency(\.databaseClient) private var databaseClient
    @Dependency(\.hapticsClient) private var hapticsClient

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
                    .send(.reading(.teardown)),
                    .send(.resetSubStates)
                )

            case .resetSubStates:
                state.readingState = .init()
                return .none

            case .syncPreviewURLs(let previewURLs):
                return .run { [galleryID = state.gallery.id] _ in
                    await databaseClient.updatePreviewURLs(gid: galleryID, previewURLs: previewURLs)
                }

            case .updateReadingProgress(let progress):
                return .run { [galleryID = state.gallery.id] _ in
                    await databaseClient.updateReadingProgress(gid: galleryID, progress: progress)
                }

            case .teardown:
                state.loadingPages.removeAll()
                state.pendingPreviewIndices.removeAll()
                state.pageErrors.removeAll()
                state.automaticallyRetriedPages.removeAll()
                var effects = CancelOperation.allCases.map {
                    Effect<Action>.cancel(id: cancelID($0, state: state))
                }
                effects.append(.send(.reading(.teardown)))
                return .merge(effects)

            case .fetchDatabaseInfos(let gid):
                guard state.databaseLoadingState == .loading else { return .none }
                if let gallery = databaseClient.fetchGallery(gid: gid) {
                    state.gallery = gallery
                }
                guard state.gallery.galleryURL != nil else {
                    state.databaseLoadingState = .idle
                    state.loadingState = .failed(.notFound)
                    return .none
                }
                return .run { send in
                    let cache = await databaseClient.fetchGalleryPreviewCache(gid: gid)
                    await send(.fetchDatabaseInfosDone(cache))
                }
                .cancellable(id: cancelID(.fetchDatabaseInfos, state: state))

            case .fetchDatabaseInfosDone(let cache):
                if let cache {
                    state.previewConfig = cache.previewConfig
                    state.previewURLs.merge(
                        cache.previewURLs,
                        uniquingKeysWith: { current, _ in current }
                    )
                }
                state.databaseLoadingState = .idle

                let firstBatchUpperBound = min(
                    state.gallery.pageCount,
                    state.previewConfig.batchSize
                )
                var indicesToFetch = state.pendingPreviewIndices
                state.pendingPreviewIndices.removeAll()
                if firstBatchUpperBound >= 1,
                   let firstMissingIndex = (1...firstBatchUpperBound)
                    .first(where: { state.previewURLs[$0] == nil })
                {
                    indicesToFetch.insert(firstMissingIndex)
                }
                return .merge(
                    indicesToFetch.sorted().map { .send(.fetchPreviewURLs($0)) }
                )

            case .fetchPreviewURLs(let index):
                guard state.databaseLoadingState != .loading else {
                    state.pendingPreviewIndices.insert(index)
                    return .none
                }

                let pageNum = state.previewConfig.pageNumber(index: index)
                let batchRange = state.previewConfig.batchRange(index: index)
                let upperBound = min(batchRange.upperBound, state.gallery.pageCount)
                guard !state.loadingPages.contains(pageNum),
                      batchRange.lowerBound <= upperBound,
                      (batchRange.lowerBound...upperBound)
                        .contains(where: { state.previewURLs[$0] == nil }),
                      let galleryURL = state.gallery.galleryURL
                else { return .none }

                state.pageErrors.removeValue(forKey: pageNum)
                state.loadingPages.insert(pageNum)
                state.updateLoadingState()
                return .run { send in
                    let response = await GalleryPreviewURLsRequest(galleryURL: galleryURL, pageNum: pageNum).response()
                    await send(.fetchPreviewURLsDone(pageNum, response))
                }
                .cancellable(id: cancelID(.fetchPreviewURLs, state: state))

            case .fetchPreviewURLsDone(let pageNum, let result):
                state.loadingPages.remove(pageNum)

                switch result {
                case .success(let previewURLs):
                    guard !previewURLs.isEmpty else {
                        return retryFailedPage(
                            pageNum: pageNum, error: .notFound, state: &state
                        )
                    }
                    state.pageErrors.removeValue(forKey: pageNum)
                    state.automaticallyRetriedPages.remove(pageNum)
                    state.updatePreviewURLs(previewURLs)
                    state.updateLoadingState()
                    return .send(.syncPreviewURLs(previewURLs))
                case .failure(let error):
                    return retryFailedPage(pageNum: pageNum, error: error, state: &state)
                }

            case .reading(.onPerformDismiss):
                return .send(.setNavigation(nil))

            case .reading:
                return .none
            }
        }
        .haptics(
            unwrapping: \.route,
            case: \.reading,
            hapticsClient: hapticsClient
        )

        Scope(state: \.readingState, action: \.reading, child: ReadingReducer.init)
    }

    private func retryFailedPage(
        pageNum: Int,
        error: AppError,
        state: inout State
    ) -> Effect<Action> {
        state.pageErrors[pageNum] = error
        state.updateLoadingState()

        guard error.isRetryable,
              state.automaticallyRetriedPages.insert(pageNum).inserted
        else { return .none }

        let retryIndex = pageNum * state.previewConfig.batchSize + 1
        return .run { send in
            try await Task.sleep(for: .milliseconds(800))
            await send(.fetchPreviewURLs(retryIndex))
        }
        .cancellable(id: cancelID(.fetchPreviewURLs, state: state))
    }

    private func cancelID(_ operation: CancelOperation, state: State) -> CancelID {
        CancelID(scope: state.cancellationScope, operation: operation)
    }
}
