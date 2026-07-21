//
//  HomeView.swift
//  EhPanda
//

import SwiftUI
import Kingfisher
import SFSafeSymbols
import ComposableArchitecture

struct HomeView: View {
    @Bindable private var store: StoreOf<HomeReducer>
    private let user: User
    @Binding private var setting: Setting
    private let blurRadius: Double
    private let tagTranslator: TagTranslator

    init(
        store: StoreOf<HomeReducer>,
        user: User, setting: Binding<Setting>, blurRadius: Double, tagTranslator: TagTranslator
    ) {
        self.store = store
        self.user = user
        _setting = setting
        self.blurRadius = blurRadius
        self.tagTranslator = tagTranslator
    }

    // MARK: HomeView
    var body: some View {
        NavigationStack {
            content
                .navigationDestination(item: navigationRoute) { route in
                    destination(for: route)
                }
                .adaptiveGalleryDetail(
                    selection: detailRoute,
                    blurRadius: blurRadius
                ) { gid in
                    GalleryDetailContainer(
                        gid: gid, user: user, setting: $setting,
                        blurRadius: blurRadius, tagTranslator: tagTranslator
                    )
                }
        }
    }

    private var content: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 28) {
                    if !store.popularGalleries.isEmpty {
                        CardSlideSection(
                            galleries: store.popularGalleries,
                            navigateAction: navigateTo(gid:)
                        )
                        .equatable()
                    }
                    if store.frontpageGalleries.count > 1 {
                        CoverWallSection(
                            galleries: store.frontpageGalleries,
                            isLoading: store.frontpageLoadingState == .loading,
                            navigateAction: navigateTo(gid:),
                            showAllAction: { store.send(.setNavigation(.section(.frontpage))) },
                            reloadAction: { store.send(.fetchFrontpageGalleries) }
                        )
                    }
                    ToplistsSection(
                        galleries: store.toplistsGalleries,
                        isLoading: !store.toplistsLoadingState
                            .values.allSatisfy({ $0 != .loading }),
                        navigateAction: navigateTo(gid:),
                        showAllAction: { store.send(.setNavigation(.section(.toplists))) },
                        reloadAction: { store.send(.fetchAllToplistsGalleries) }
                    )
                    .equatable()
                }
                .padding(.vertical, 12)
            }
            .opacity(store.popularGalleries.isEmpty ? 0 : 1)
            .zIndex(2)

            LoadingView()
                .opacity(
                    store.popularLoadingState == .loading
                    && store.popularGalleries.isEmpty ? 1 : 0
                )
                .zIndex(0)

            let error = store.popularLoadingState.failed
            ErrorView(error: error ?? .unknown) {
                store.send(.fetchAllGalleries)
            }
            .opacity(store.popularGalleries.isEmpty && error != nil ? 1 : 0)
            .zIndex(1)
        }
        .animation(.default, value: store.popularLoadingState)
        .onAppear {
            if store.popularGalleries.isEmpty {
                store.send(.fetchAllGalleries)
            }
        }
        .navigationTitle(L10n.Localizable.HomeView.Title.home)
    }

    private var navigationRoute: Binding<HomeReducer.Route?> {
        Binding(
            get: {
                guard let route = store.route else { return nil }
                if case .section = route { return route }
                return nil
            },
            set: { route in
                store.send(.setNavigation(route))
            }
        )
    }

    private var detailRoute: Binding<String?> {
        Binding(
            get: {
                guard case .detail(let gid) = store.route else { return nil }
                return gid
            },
            set: { gid in
                store.send(.setNavigation(gid.map(HomeReducer.Route.detail)))
            }
        )
    }

}

// MARK: Navigation
private extension HomeView {
    @ViewBuilder func destination(for route: HomeReducer.Route) -> some View {
        switch route {
        case .detail(let gid):
            GalleryDetailContainer(
                gid: gid, user: user, setting: $setting,
                blurRadius: blurRadius, tagTranslator: tagTranslator
            )
        case .section(let section):
            switch section {
            case .frontpage:
                FrontpageView(
                    store: store.scope(state: \.frontpageState, action: \.frontpage),
                    user: user, setting: $setting, blurRadius: blurRadius, tagTranslator: tagTranslator
                )
            case .toplists:
                ToplistsView(
                    store: store.scope(state: \.toplistsState, action: \.toplists),
                    user: user, setting: $setting, blurRadius: blurRadius, tagTranslator: tagTranslator
                )
            }
        }
    }

    func navigateTo(gid: String) {
        store.send(.setNavigation(.detail(gid)))
    }
}

private struct HomePressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

// MARK: CardSlideSection
private struct CardSlideSection: View, Equatable {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let galleries: [Gallery]
    private let navigateAction: (String) -> Void

    init(
        galleries: [Gallery],
        navigateAction: @escaping (String) -> Void
    ) {
        self.galleries = galleries
        self.navigateAction = navigateAction
    }

    private var cardHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 280 : Defaults.FrameSize.cardCellHeight
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.galleries.count == rhs.galleries.count else { return false }
        return zip(lhs.galleries, rhs.galleries).allSatisfy { lhs, rhs in
            lhs.id == rhs.id
                && lhs.title == rhs.title
                && lhs.rating == rhs.rating
                && lhs.coverURL == rhs.coverURL
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let cardWidth = min(max(proxy.size.width - 48, 1), 620)
            let horizontalMargin = max((proxy.size.width - cardWidth) / 2, 16)

            GlassEffectContainer(spacing: 12) {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(galleries) { gallery in
                            Button {
                                navigateAction(gallery.id)
                            } label: {
                                GalleryCardCell(
                                    gallery: gallery,
                                    width: cardWidth,
                                    height: cardHeight
                                )
                                .tint(.primary)
                                .multilineTextAlignment(.leading)
                            }
                            .buttonStyle(.plain)
                            .galleryContextMenu(gallery: gallery)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, horizontalMargin, for: .scrollContent)
                .scrollTargetBehavior(
                    .viewAligned(limitBehavior: .alwaysByOne, anchor: .center)
                )
            }
        }
        .frame(height: cardHeight)
    }
}

// MARK: CoverWallSection
private struct CoverWallSection: View {
    private let galleries: [Gallery]
    private let isLoading: Bool
    private let navigateAction: (String) -> Void
    private let showAllAction: () -> Void
    private let reloadAction: () -> Void

    init(
        galleries: [Gallery], isLoading: Bool,
        navigateAction: @escaping (String) -> Void,
        showAllAction: @escaping () -> Void,
        reloadAction: @escaping () -> Void
    ) {
        self.galleries = galleries
        self.isLoading = isLoading
        self.navigateAction = navigateAction
        self.showAllAction = showAllAction
        self.reloadAction = reloadAction
    }

    private var dataSource: [[Gallery]] {
        var galleries = galleries
        if galleries.isEmpty {
            galleries = Gallery.mockGalleries(count: 25)
        }
        if galleries.count % 2 != 0 { galleries = galleries.dropLast() }
        return stride(from: 0, to: galleries.count, by: 2).map { index in
            [galleries[index], galleries[index + 1]]
        }
    }

    var body: some View {
        SubSection(
            title: L10n.Localizable.HomeView.Section.Title.frontpage,
            isLoading: isLoading,
            reloadAction: reloadAction,
            showAllAction: showAllAction
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(dataSource, id: \.first) {
                        VerticalCoverStack(galleries: $0, navigateAction: navigateAction)
                    }
                }
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .frame(height: Defaults.ImageSize.rowH * 2 + 12)
        }
    }
}

private struct VerticalCoverStack: View {
    private let galleries: [Gallery]
    private let navigateAction: (String) -> Void

    init(galleries: [Gallery], navigateAction: @escaping (String) -> Void) {
        self.galleries = galleries
        self.navigateAction = navigateAction
    }

    private func placeholder() -> some View {
        Placeholder(style: .activity(ratio: Defaults.ImageSize.headerAspect))
    }
    private func imageContainer(gallery: Gallery) -> some View {
        Button {
            navigateAction(gallery.id)
        } label: {
            KFImage(gallery.coverURL)
                .placeholder(placeholder)
                .defaultModifier()
                .scaledToFill()
                .frame(width: Defaults.ImageSize.rowW, height: Defaults.ImageSize.rowH)
                .clipShape(.rect(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(uiColor: .separator).opacity(0.3), lineWidth: 0.5)
                }
        }
        .buttonStyle(HomePressableButtonStyle())
        .galleryContextMenu(gallery: gallery)
    }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(galleries, content: imageContainer)
        }
    }
}

// MARK: ToplistsSection
private struct ToplistsSection: View, Equatable {
    private let galleries: [Int: [Gallery]]
    private let isLoading: Bool
    private let navigateAction: (String) -> Void
    private let showAllAction: () -> Void
    private let reloadAction: () -> Void

    private static let placeholderDataSource: [Int: [Gallery]] = {
        var gallery: Gallery = .empty
        gallery.title = "......"
        gallery.uploader = "......"
        let galleries = Array(repeating: gallery, count: 6)
        return Dictionary(
            uniqueKeysWithValues: ToplistsType.allCases.map {
                ($0.categoryIndex, galleries)
            }
        )
    }()

    init(
        galleries: [Int: [Gallery]], isLoading: Bool,
        navigateAction: @escaping (String) -> Void,
        showAllAction: @escaping () -> Void,
        reloadAction: @escaping () -> Void
    ) {
        self.galleries = galleries
        self.isLoading = isLoading
        self.navigateAction = navigateAction
        self.showAllAction = showAllAction
        self.reloadAction = reloadAction
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.isLoading == rhs.isLoading else { return false }
        let visibleCount = DeviceUtil.isPad ? 6 : 3
        return ToplistsType.allCases.allSatisfy { type in
            visibleGalleriesEqual(
                lhs.galleries[type.categoryIndex],
                rhs.galleries[type.categoryIndex],
                maximumCount: visibleCount
            )
        }
    }

    private static func visibleGalleriesEqual(
        _ lhs: [Gallery]?,
        _ rhs: [Gallery]?,
        maximumCount: Int
    ) -> Bool {
        let lhs = (lhs ?? []).prefix(maximumCount)
        let rhs = (rhs ?? []).prefix(maximumCount)
        return lhs.elementsEqual(rhs) { lhs, rhs in
            lhs.id == rhs.id
                && lhs.title == rhs.title
                && lhs.uploader == rhs.uploader
                && lhs.coverURL == rhs.coverURL
        }
    }

    private var dataSource: [Int: [Gallery]] {
        galleries.isEmpty ? Self.placeholderDataSource : galleries
    }
    private func galleries(type: ToplistsType, range: ClosedRange<Int>) -> [Gallery] {
        let galleries = dataSource[type.categoryIndex] ?? []
        guard galleries.count > range.upperBound else { return [] }
        return Array(galleries[range])
    }

    var body: some View {
        SubSection(
            title: L10n.Localizable.HomeView.Section.Title.toplists,
            isLoading: isLoading,
            reloadAction: reloadAction,
            showAllAction: showAllAction
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(ToplistsType.allCases, content: verticalStacks)
                }
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
        }
    }
    private func verticalStacks(type: ToplistsType) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(type.value)
                .font(.headline)
            HStack(spacing: 20) {
                VerticalToplistsStack(
                    galleries: galleries(type: type, range: 0...2), startRanking: 1,
                    navigateAction: navigateAction
                )
                if DeviceUtil.isPad {
                    VerticalToplistsStack(
                        galleries: galleries(type: type, range: 3...5), startRanking: 4,
                        navigateAction: navigateAction
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct VerticalToplistsStack: View {
    private let galleries: [Gallery]
    private let startRanking: Int
    private let navigateAction: (String) -> Void

    init(galleries: [Gallery], startRanking: Int, navigateAction: @escaping (String) -> Void) {
        self.galleries = galleries
        self.startRanking = startRanking
        self.navigateAction = navigateAction
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<galleries.count, id: \.self) { index in
                VStack(spacing: 10) {
                    Button {
                        navigateAction(galleries[index].id)
                    } label: {
                        GalleryRankingCell(gallery: galleries[index], ranking: startRanking + index)
                            .equatable()
                            .tint(.primary)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .galleryContextMenu(gallery: galleries[index])
                    if index != galleries.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .frame(width: Defaults.FrameSize.rankingCellWidth)
    }
}

enum HomeSectionType: String, CaseIterable, Identifiable {
    var id: String { rawValue }

    case frontpage
    case toplists
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView(
            store: .init(initialState: .init(), reducer: HomeReducer.init),
            user: .init(),
            setting: .constant(.init()),
            blurRadius: 0,
            tagTranslator: .init()
        )
    }
}
