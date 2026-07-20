//
//  CacheReducer.swift
//  EhPanda
//

import ComposableArchitecture

@Reducer
struct CacheReducer {
    @CasePathable
    enum Route: Equatable {
        case detail(String)
    }

    private enum CancelID {
        case observeUpdates
    }

    @ObservableState
    struct State: Equatable {
        var route: Route?
        var items = [GalleryCacheItem]()
        var searchText = ""
        var hasStartedObservation = false
        var hasRefreshedLibrary = false
        var hasRestoredDownloads = false

        var filteredItems: [GalleryCacheItem] {
            guard !searchText.isEmpty else { return items }
            return items.filter {
                $0.displayTitle.localizedCaseInsensitiveContains(searchText)
                    || $0.gallery.uploader?.localizedCaseInsensitiveContains(searchText) == true
                    || $0.id.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case onAppear(CacheDownloadOptions, resumesAutomatically: Bool)
        case observeUpdates
        case itemsUpdated([GalleryCacheItem])
        case refresh

        case setNavigation(Route?)
        case openDetail(String)
        case openDetailPrepared(String)
        case clearSubStates

        case pause(String)
        case pauseAll
        case resume(String, CacheDownloadOptions)
        case resumeAll(CacheDownloadOptions)
        case delete(String)
        case deleteAll

    }

    @Dependency(\.cacheClient) private var cacheClient
    @Dependency(\.databaseClient) private var databaseClient

    var body: some Reducer<State, Action> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .onAppear(let options, let resumesAutomatically):
                var effects = [Effect<Action>]()
                if !state.hasStartedObservation {
                    state.hasStartedObservation = true
                    effects.append(.send(.observeUpdates))
                }
                let shouldRefreshLibrary = !state.hasRefreshedLibrary
                if shouldRefreshLibrary {
                    state.hasRefreshedLibrary = true
                }
                let shouldRestoreDownloads = !state.hasRestoredDownloads && resumesAutomatically
                if !state.hasRestoredDownloads {
                    state.hasRestoredDownloads = true
                }
                if shouldRefreshLibrary || shouldRestoreDownloads {
                    effects.append(.run { send in
                        await send(.itemsUpdated(await cacheClient.items()))
                        if shouldRefreshLibrary {
                            await cacheClient.refresh()
                        }
                        if shouldRestoreDownloads {
                            await cacheClient.restoreInterrupted(options)
                        }
                    })
                }
                return effects.isEmpty ? .none : .merge(effects)

            case .observeUpdates:
                return .run { send in
                    let stream = await cacheClient.updates()
                    for await items in stream {
                        await send(.itemsUpdated(items))
                    }
                }
                .cancellable(id: CancelID.observeUpdates, cancelInFlight: true)

            case .itemsUpdated(let items):
                state.items = items
                return .none

            case .refresh:
                return .run { _ in await cacheClient.refresh() }

            case .setNavigation(let route):
                state.route = route
                return route == nil ? .send(.clearSubStates) : .none

            case .openDetail(let gid):
                guard let item = state.items.first(where: { $0.id == gid }) else { return .none }
                let hasGallery = databaseClient.fetchGallery(gid: gid) != nil
                let hasDetail = databaseClient.fetchGalleryDetail(gid: gid) != nil
                return .run { send in
                    if !hasGallery {
                        await databaseClient.cacheGalleries([item.gallery])
                    } else {
                        await databaseClient.updateGallery(
                            gid: gid,
                            key: "pageCount",
                            value: Int64(item.pageCount)
                        )
                    }
                    if !hasDetail {
                        await databaseClient.cacheGalleryDetail(item.detail)
                    }
                    await send(.openDetailPrepared(gid))
                }

            case .openDetailPrepared(let gid):
                return .send(.setNavigation(.detail(gid)))

            case .clearSubStates:
                return .none

            case .pause(let gid):
                return .run { _ in await cacheClient.pause(gid) }

            case .pauseAll:
                return .run { _ in await cacheClient.pauseAll() }

            case .resume(let gid, let options):
                return .run { _ in await cacheClient.resume(gid, options) }

            case .resumeAll(let options):
                return .run { _ in await cacheClient.resumeAll(options) }

            case .delete(let gid):
                if case .detail(let currentGID) = state.route, currentGID == gid {
                    state.route = nil
                }
                return .run { _ in await cacheClient.delete(gid) }

            case .deleteAll:
                state.route = nil
                return .run { _ in await cacheClient.deleteAll() }

            }
        }
    }
}
