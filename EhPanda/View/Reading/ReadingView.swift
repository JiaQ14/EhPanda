//
//  ReadingView.swift
//  EhPanda
//

import SwiftUI
import AppIntents
import ComposableArchitecture

struct ReadingView: View {
    @Bindable var store: StoreOf<ReadingReducer>
    private let gid: String
    @Binding private var setting: Setting
    private let blurRadius: Double

    @StateObject private var autoPlayHandler = AutoPlayHandler()
    @StateObject private var gestureHandler = GestureHandler()
    @StateObject private var pageHandler = PageHandler()
    @State private var pageIndex = 0
    @State private var enablesLiveText = false

    init(
        store: StoreOf<ReadingReducer>,
        gid: String, setting: Binding<Setting>, blurRadius: Double
    ) {
        self.store = store
        self.gid = gid
        _setting = setting
        self.blurRadius = blurRadius
    }

    private let backgroundColor = Color.black
    private let backgroundUIColor = UIColor.black

    var body: some View {
        changeTriggers(content: { content })
            .userActivity(
                "com.zjq9714.ehpanda.gallery.reading",
                element: screenGalleryEntity
            ) { entity, activity in
                activity.title = entity.title
                activity.appEntityIdentifier = EntityIdentifier(for: entity)
                activity.userInfo = ["gid": entity.id]
            }
            .sheet(isPresented: isReadingSettingPresented) {
                NavigationStack {
                    ReadingSettingView(
                        readingDirection: $setting.readingDirection,
                        prefetchLimit: $setting.prefetchLimit,
                        enablesLandscape: $setting.enablesLandscape,
                        avoidsStatusBarInVerticalMode: $setting.avoidsStatusBarInVerticalMode,
                        contentDividerHeight: $setting.contentDividerHeight,
                        maximumScaleFactor: $setting.maximumScaleFactor,
                        doubleTapScaleFactor: $setting.doubleTapScaleFactor
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(role: .cancel) {
                                store.send(.setNavigation(nil))
                            } label: {
                                Image(systemSymbol: .xmark)
                            }
                        }
                    }
                }
                .accentColor(setting.accentColor)
                .tint(setting.accentColor)
                .autoBlur(radius: blurRadius)
            }
            .sheet(item: $store.route.sending(\.setNavigation).share) { shareItemBox in
                ActivityView(activityItems: [shareItemBox.wrappedValue.associatedValue])
                    .accentColor(setting.accentColor)
                    .autoBlur(radius: blurRadius)
            }
            .progressHUD(
                config: store.hudConfig,
                unwrapping: $store.route,
                case: \.hud
            )

            .animation(.default, value: enablesLiveText)
            .animation(.default, value: store.showsPanel)
            .statusBar(hidden: !store.showsPanel)
            .onDisappear {
                setAutoPlayPolocy(.off)
            }
            .onAppear { store.send(.onAppear(gid, setting.enablesLandscape)) }
            .onKeyPress(.leftArrow) {
                updatePageIndex(
                    pageIndex + (setting.readingDirection == .rightToLeft ? 1 : -1)
                )
                return .handled
            }
            .onKeyPress(.rightArrow) {
                updatePageIndex(
                    pageIndex + (setting.readingDirection == .rightToLeft ? -1 : 1)
                )
                return .handled
            }
            .onKeyPress(.space) {
                updatePageIndex(pageIndex + 1)
                return .handled
            }
            .onKeyPress(.escape) {
                store.send(.onPerformDismiss)
                return .handled
            }
    }

    private var screenGalleryEntity: GalleryEntity? {
        guard !store.gallery.id.isEmpty else { return nil }
        return GalleryEntity(gallery: store.gallery)
    }

    private var isReadingSettingPresented: Binding<Bool> {
        Binding(
            get: {
                guard case .readingSetting = store.route else { return false }
                return true
            },
            set: { isPresented in
                guard !isPresented, case .readingSetting = store.route else { return }
                store.send(.setNavigation(nil))
            }
        )
    }

    var content: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            GeometryReader { proxy in
                let pages = store.state.containerDataSource(setting: setting)
                let isVertical = setting.readingDirection == .vertical
                let isDualPage =
                    setting.enablesDualPageMode
                    && !isVertical
                    && DeviceUtil.isLandscape
                let cacheDirectoryIdentifier = store.cacheDirectoryIdentifier
                let cachePageIdentifiers = store.cachePageIdentifiers

                ReadingCollectionView(
                    pageIndex: $pageIndex,
                    pages: pages,
                    axis: isVertical ? .vertical : .horizontal,
                    isRightToLeft: setting.readingDirection == .rightToLeft,
                    spacing: setting.contentDividerHeight,
                    topInset: isVertical && setting.avoidsStatusBarInVerticalMode
                        ? proxy.safeAreaInsets.top : 0,
                    isDualPage: isDualPage,
                    isDatabaseLoading: store.databaseLoadingState != .idle,
                    isScrollEnabled: gestureHandler.scale == 1,
                    reloadID: store.forceRefreshID,
                    backgroundColor: backgroundUIColor,
                    pageModel: {
                        readingPageModel(index: $0)
                    },
                    fetchAction: { store.send(.fetchImageURLs($0)) },
                    refetchAction: { store.send(.refetchImageURLs($0)) },
                    prefetchAction: {
                        store.send(.prefetchImages($0, setting.prefetchLimit))
                    },
                    retryAction: { store.send(.retryImage($0)) },
                    loadSucceededAction: {
                        store.send(.onWebImageSucceeded($0))
                    },
                    loadFailedAction: {
                        store.send(
                            .onWebImageFailed(
                                $0,
                                $1,
                                cacheDirectoryIdentifier,
                                cachePageIdentifiers[$0]
                            )
                        )
                    },
                    copyImageAction: { store.send(.copyImage($0)) },
                    saveImageAction: { store.send(.saveImage($0)) },
                    shareImageAction: { store.send(.shareImage($0)) }
                )
                .scaleEffect(gestureHandler.scale, anchor: gestureHandler.scaleAnchor)
                .offset(gestureHandler.offset)
                .highPriorityGesture(
                    dragGesture.simultaneously(with: tapGesture),
                    isEnabled: gestureHandler.scale > 1 && !enablesLiveText
                )
                .highPriorityGesture(
                    dragGesture,
                    isEnabled: gestureHandler.scale > 1 && enablesLiveText
                )
                .simultaneousGesture(
                    tapGesture,
                    isEnabled: gestureHandler.scale == 1 && !enablesLiveText
                )
                .simultaneousGesture(magnificationGesture)
                .ignoresSafeArea()
            }

            ControlPanel(
                showsPanel: $store.showsPanel,
                showsSliderPreview: $store.showsSliderPreview,
                sliderValue: $pageHandler.sliderValue, setting: $setting,
                enablesLiveText: $enablesLiveText,
                autoPlayPolicy: .init(get: { autoPlayHandler.policy }, set: { setAutoPlayPolocy($0) }),
                range: 1...Float(store.gallery.pageCount),
                previewURLs: store.previewURLs,
                dismissAction: { store.send(.onPerformDismiss) },
                navigateSettingAction: { store.send(.setNavigation(.readingSetting())) },
                reloadAllImagesAction: { store.send(.reloadAllWebImages) },
                retryAllFailedImagesAction: { store.send(.retryAllFailedWebImages) },
                fetchPreviewURLsAction: { store.send(.fetchPreviewURLs($0)) }
            )
        }
    }

    @ViewBuilder
    private func changeTriggers<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
             // Page
            .onChange(of: pageIndex) { _, newValue in
                Logger.info("pageIndex changed", context: ["pageIndex": newValue])
                let newValue = pageHandler.mapFromPager(
                    index: newValue, pageCount: store.gallery.pageCount, setting: setting
                )
                pageHandler.sliderValue = .init(newValue)
                if store.databaseLoadingState == .idle {
                    store.send(.syncReadingProgress(.init(newValue)))
                }
            }
            .onChange(of: pageHandler.sliderValue) { _, newValue in
                Logger.info("pageHandler.sliderValue changed", context: ["sliderValue": newValue])
                if !store.showsSliderPreview {
                    setPageIndex(sliderValue: newValue)
                }
            }
            .onChange(of: store.showsSliderPreview) { _, newValue in
                Logger.info("store.showsSliderPreview changed", context: ["isShown": newValue])
                if !newValue { setPageIndex(sliderValue: pageHandler.sliderValue) }
                setAutoPlayPolocy(.off)
            }
            .onChange(of: store.readingProgress) { _, newValue in
                Logger.info("store.readingProgress changed", context: ["readingProgress": newValue])
                pageHandler.sliderValue = .init(newValue)
            }
            .onChange(of: setting.readingDirection) {
                setPageIndex(sliderValue: pageHandler.sliderValue)
            }
            .onChange(of: setting.enablesDualPageMode) {
                setPageIndex(sliderValue: pageHandler.sliderValue)
            }
            .onChange(of: setting.exceptCover) {
                setPageIndex(sliderValue: pageHandler.sliderValue)
            }

            // AutoPlay
            .onChange(of: store.route) { _, newValue in
                Logger.info("store.route changed", context: ["route": newValue])
                if ![.hud, .none].contains(newValue) {
                    setAutoPlayPolocy(.off)
                }
            }

            // Orientation
            .onChange(of: setting.enablesLandscape) { _, newValue in
                Logger.info("setting.enablesLandscape changed", context: ["newValue": newValue])
                store.send(.setOrientationPortrait(!newValue))
            }
    }

    private func readingPageModel(index: Int) -> ReadingPageModel {
        let imageStackConfig = store.state.imageContainerConfigs(index: index, setting: setting)
        return ReadingPageModel(
            first: imageStackConfig.isFirstAvailable
                ? readingImageModel(index: imageStackConfig.firstIndex)
                : nil,
            second: imageStackConfig.isSecondAvailable
                ? readingImageModel(index: imageStackConfig.secondIndex)
                : nil
        )
    }

    private func readingImageModel(index: Int) -> ReadingImageModel {
        .init(
            index: index,
            imageURL: store.imageURLs[index],
            originalImageURL: store.originalImageURLs[index],
            loadingState: store.imageURLLoadingStates[index] ?? .idle,
            enablesLiveText: enablesLiveText
        )
    }
}

// MARK: Handler methods
extension ReadingView {
    func setPageIndex(sliderValue: Float) {
        let newValue = pageHandler.mapToPager(
            index: .init(sliderValue), setting: setting
        )
        if pageIndex != newValue {
            updatePageIndex(newValue)
            Logger.info("Reader.update", context: ["update": newValue])
        }
    }
    func setAutoPlayPolocy(_ policy: AutoPlayPolicy) {
        autoPlayHandler.setPolicy(policy, updatePageAction: {
            updatePageIndex(pageIndex + 1)
            Logger.info("Reader.update", context: ["update": "next"])
        })
    }
    func updatePageIndex(_ newValue: Int) {
        let pageCount = store.state.containerDataSource(setting: setting).count
        guard pageCount > 0 else {
            pageIndex = 0
            return
        }
        pageIndex = min(max(newValue, 0), pageCount - 1)
    }
}

// MARK: Gesture
extension ReadingView {
    var tapGesture: some Gesture {
        let singleTap = TapGesture(count: 1)
            .onEnded {
                gestureHandler.onSingleTapGestureEnded(
                    readingDirection: setting.readingDirection,
                    setPageIndexOffsetAction: {
                        let newValue = pageIndex + $0
                        updatePageIndex(newValue)
                        Logger.info("Reader.update", context: ["update": newValue])
                    },
                    toggleShowsPanelAction: { store.send(.toggleShowsPanel) }
                )
            }
        let doubleTap = TapGesture(count: 2)
            .onEnded {
                withAnimation(.easeOut(duration: 0.2)) {
                    gestureHandler.onDoubleTapGestureEnded(
                        scaleMaximum: setting.maximumScaleFactor,
                        doubleTapScale: setting.doubleTapScaleFactor
                    )
                }
            }
        return ExclusiveGesture(doubleTap, singleTap)
    }
    var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged {
                gestureHandler.onMagnificationGestureChanged(
                    value: $0, scaleMaximum: setting.maximumScaleFactor
                )
            }
            .onEnded { value in
                withAnimation(.easeOut(duration: 0.2)) {
                    gestureHandler.onMagnificationGestureEnded(
                        value: value, scaleMaximum: setting.maximumScaleFactor
                    )
                }
            }
    }
    var dragGesture: some Gesture {
        DragGesture(minimumDistance: .zero, coordinateSpace: .local)
            .onChanged(gestureHandler.onDragGestureChanged)
            .onEnded(gestureHandler.onDragGestureEnded)
    }
}

// MARK: Definition
struct ImageStackConfig {
    let firstIndex: Int
    let secondIndex: Int
    let isFirstAvailable: Bool
    let isSecondAvailable: Bool
}

struct ReadingPageModel: Equatable {
    let first: ReadingImageModel?
    let second: ReadingImageModel?

    var images: [ReadingImageModel] {
        [first, second].compactMap { $0 }
    }
}

struct ReadingImageModel: Equatable {
    let index: Int
    let imageURL: URL?
    let originalImageURL: URL?
    let loadingState: LoadingState
    let enablesLiveText: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.index == rhs.index
            && lhs.imageURL == rhs.imageURL
            && lhs.originalImageURL == rhs.originalImageURL
            && lhs.loadingState == rhs.loadingState
            && lhs.enablesLiveText == rhs.enablesLiveText
    }
}

enum AutoPlayPolicy: Int, CaseIterable, Identifiable {
    var id: Int { rawValue }

    case off = -1
    case sec1 = 1
    case sec2 = 2
    case sec3 = 3
    case sec4 = 4
    case sec5 = 5
}

extension AutoPlayPolicy {
    var value: String {
        switch self {
        case .off:
            return L10n.Localizable.Enum.AutoPlayPolicy.Value.off
        default:
            return L10n.Localizable.Common.Value.seconds("\(rawValue)")
        }
    }
}

struct ReadingView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            Text("")
                .fullScreenCover(isPresented: .constant(true)) {
                    ReadingView(
                        store: .init(initialState: .init(gallery: .empty), reducer: ReadingReducer.init),
                        gid: .init(),
                        setting: .constant(.init()),
                        blurRadius: 0
                    )
                }
        }
    }
}
