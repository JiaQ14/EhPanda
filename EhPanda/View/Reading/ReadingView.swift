//
//  ReadingView.swift
//  EhPanda
//

import SwiftUI
import Kingfisher
import SwiftUIPager
import ComposableArchitecture

struct ReadingView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    @Bindable var store: StoreOf<ReadingReducer>
    private let gid: String
    @Binding private var setting: Setting
    private let blurRadius: Double

    @StateObject private var liveTextHandler = LiveTextHandler()
    @StateObject private var autoPlayHandler = AutoPlayHandler()
    @StateObject private var gestureHandler = GestureHandler()
    @StateObject private var pageHandler = PageHandler()
    @StateObject private var page: Page = .first()

    init(
        store: StoreOf<ReadingReducer>,
        gid: String, setting: Binding<Setting>, blurRadius: Double
    ) {
        self.store = store
        self.gid = gid
        _setting = setting
        self.blurRadius = blurRadius
    }

    private var backgroundColor: Color {
        colorScheme == .light ? Color(.systemGray4) : Color(.systemGray6)
    }

    var body: some View {
        changeTriggers(content: { content })
            .sheet(item: $store.route.sending(\.setNavigation).readingSetting) { _ in
                NavigationView {
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
                        if !DeviceUtil.isPad && DeviceUtil.isLandscape {
                            CustomToolbarItem(placement: .cancellationAction) {
                                Button {
                                    store.send(.setNavigation(nil))
                                } label: {
                                    Image(systemSymbol: .chevronDown)
                                }
                            }
                        }
                    }
                }
                .accentColor(setting.accentColor)
                .tint(setting.accentColor)
                .autoBlur(radius: blurRadius)
                .navigationViewStyle(.stack)
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

            .animation(.default, value: liveTextHandler.enablesLiveText)
            .animation(.default, value: liveTextHandler.liveTextGroups)
            .animation(.default, value: store.showsPanel)
            .statusBar(hidden: !store.showsPanel)
            .onDisappear {
                liveTextHandler.cancelRequests()
                setAutoPlayPolocy(.off)
            }
            .onAppear { store.send(.onAppear(gid, setting.enablesLandscape)) }
    }

    var content: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            GeometryReader { proxy in
                ZStack {
                    if setting.readingDirection == .vertical {
                        AdvancedList(
                            page: page,
                            data: store.state.containerDataSource(setting: setting),
                            id: \.self,
                            spacing: setting.contentDividerHeight,
                            topContentInset: setting.avoidsStatusBarInVerticalMode
                                ? proxy.safeAreaInsets.top : 0,
                            content: imageStack
                        )
                        .scrollDisabled(gestureHandler.scale != 1)
                    } else {
                        Pager(
                            page: page,
                            data: store.state.containerDataSource(setting: setting),
                            id: \.self,
                            content: imageStack
                        )
                        .horizontal(setting.readingDirection == .rightToLeft ? .endToStart : .startToEnd)
                        .swipeInteractionArea(.allAvailable)
                        .allowsDragging(gestureHandler.scale == 1)
                    }
                }
                .scaleEffect(gestureHandler.scale, anchor: gestureHandler.scaleAnchor)
                .offset(gestureHandler.offset)
                .highPriorityGesture(
                    dragGesture.simultaneously(with: tapGesture),
                    isEnabled: gestureHandler.scale > 1
                )
                .simultaneousGesture(tapGesture, isEnabled: gestureHandler.scale == 1)
                .simultaneousGesture(magnificationGesture)
                .ignoresSafeArea()
            }
            .id(store.databaseLoadingState)
            .id(store.forceRefreshID)

            ControlPanel(
                showsPanel: $store.showsPanel,
                showsSliderPreview: $store.showsSliderPreview,
                sliderValue: $pageHandler.sliderValue, setting: $setting,
                enablesLiveText: $liveTextHandler.enablesLiveText,
                autoPlayPolicy: .init(get: { autoPlayHandler.policy }, set: { setAutoPlayPolocy($0) }),
                range: 1...Float(store.gallery.pageCount),
                previewURLs: store.previewURLs,
                dismissGesture: controlPanelDismissGesture,
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
            .onChange(of: page.index) { _, newValue in
                Logger.info("page.index changed", context: ["pageIndex": newValue])
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

            // AutoPlay
            .onChange(of: store.route) { _, newValue in
                Logger.info("store.route changed", context: ["route": newValue])
                if ![.hud, .none].contains(newValue) {
                    setAutoPlayPolocy(.off)
                }
            }

            // LiveText
            .onChange(of: liveTextHandler.enablesLiveText) { _, newValue in
                Logger.info("liveTextHandler.enablesLiveText changed", context: ["isEnabled": newValue])
                if newValue { store.webImageLoadSuccessIndices.forEach(analyzeImageForLiveText) }
            }
            .onChange(of: store.webImageLoadSuccessIndices) { _, newValue in
                Logger.info("store.webImageLoadSuccessIndices changed", context: [
                    "count": store.webImageLoadSuccessIndices.count
                ])
                if liveTextHandler.enablesLiveText {
                    newValue.forEach(analyzeImageForLiveText)
                }
            }

            // Orientation
            .onChange(of: setting.enablesLandscape) { _, newValue in
                Logger.info("setting.enablesLandscape changed", context: ["newValue": newValue])
                store.send(.setOrientationPortrait(!newValue))
            }
    }

    @ViewBuilder private func imageStack(index: Int) -> some View {
        let imageStackConfig = store.state.imageContainerConfigs(index: index, setting: setting)
        let isDualPage = setting.enablesDualPageMode && setting.readingDirection != .vertical && DeviceUtil.isLandscape
        let cacheDirectoryIdentifier = store.cacheDirectoryIdentifier
        let cachePageIdentifiers = store.cachePageIdentifiers
        let pageModel = ReadingPageModel(
            first: imageStackConfig.isFirstAvailable
                ? readingImageModel(index: imageStackConfig.firstIndex)
                : nil,
            second: imageStackConfig.isSecondAvailable
                ? readingImageModel(index: imageStackConfig.secondIndex)
                : nil
        )
        HorizontalImageStack(
            index: index,
            isDualPage: isDualPage,
            isDatabaseLoading: store.databaseLoadingState != .idle,
            backgroundColor: backgroundColor,
            pageModel: pageModel,
            enablesLiveText: liveTextHandler.enablesLiveText,
            focusedLiveTextGroup: liveTextHandler.focusedLiveTextGroup,
            liveTextTapAction: liveTextHandler.setFocusedLiveTextGroup,
            fetchAction: { store.send(.fetchImageURLs($0)) },
            refetchAction: { store.send(.refetchImageURLs($0)) },
            prefetchAction: { store.send(.prefetchImages($0, setting.prefetchLimit)) },
            loadRetryAction: { store.send(.onWebImageRetry($0)) },
            loadSucceededAction: { store.send(.onWebImageSucceeded($0)) },
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
        .equatable()
    }

    private func readingImageModel(index: Int) -> ReadingImageModel {
        .init(
            index: index,
            imageURL: store.imageURLs[index],
            originalImageURL: store.originalImageURLs[index],
            loadingState: store.imageURLLoadingStates[index] ?? .idle,
            liveTextGroups: liveTextHandler.liveTextGroups[index] ?? []
        )
    }
}

// MARK: Handler methods
extension ReadingView {
    func setPageIndex(sliderValue: Float) {
        let newValue = pageHandler.mapToPager(
            index: .init(sliderValue), setting: setting
        )
        if page.index != newValue {
            page.update(.new(index: newValue))
            Logger.info("Pager.update", context: ["update": newValue])
        }
    }
    func setAutoPlayPolocy(_ policy: AutoPlayPolicy) {
        autoPlayHandler.setPolicy(policy, updatePageAction: {
            page.update(.next)
            Logger.info("Pager.update", context: ["update": "next"])
        })
    }
    func analyzeImageForLiveText(index: Int) {
        Logger.info("analyzeImageForLiveText", context: ["index": index])
        guard liveTextHandler.liveTextGroups[index] == nil else {
            Logger.info("analyzeImageForLiveText duplicated", context: ["index": index])
            return
        }
        guard let url = store.imageURLs[index] else {
            Logger.info("analyzeImageForLiveText URL not found", context: ["index": index])
            return
        }
        let key = url.cacheKey
        let isDualPage =
            setting.enablesDualPageMode
            && setting.readingDirection != .vertical
            && DeviceUtil.isLandscape
        let options: KingfisherOptionsInfo = url.isGIF
            ? []
            : [.processor(ReadingImageSizing.processor(
                isDualPage: isDualPage,
                displayScale: displayScale
            ))]
        KingfisherManager.shared.cache.retrieveImage(forKey: key, options: options) { result in
            switch result {
            case .success(let result):
                if let image = result.image, let cgImage = image.cgImage {
                    liveTextHandler.analyzeImage(
                        cgImage, size: image.size, index: index, recognitionLanguages:
                            store.galleryDetail?.language.codes
                    )
                } else {
                    Logger.info("analyzeImageForLiveText image not found", context: ["index": index])
                }
            case .failure(let error):
                Logger.info(
                    "analyzeImageForLiveText failed",
                    context: [
                        "index": index,
                        "error": error
                    ]
                    as [String: Any]
                )
            }
        }
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
                        let newValue = page.index + $0
                        page.update(.new(index: newValue))
                        Logger.info("Pager.update", context: ["update": newValue])
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
    var controlPanelDismissGesture: some Gesture {
        DragGesture().onEnded {
            gestureHandler.onControlPanelDismissGestureEnded(
                value: $0, dismissAction: { store.send(.onPerformDismiss) }
            )
        }
    }
}

// MARK: HorizontalImageStack
private struct HorizontalImageStack: View, Equatable {
    private let index: Int
    private let isDualPage: Bool
    private let isDatabaseLoading: Bool
    private let backgroundColor: Color
    private let pageModel: ReadingPageModel
    private let enablesLiveText: Bool
    private let focusedLiveTextGroup: LiveTextGroup?
    private let liveTextTapAction: (LiveTextGroup) -> Void
    private let fetchAction: (Int) -> Void
    private let refetchAction: (Int) -> Void
    private let prefetchAction: (Int) -> Void
    private let loadRetryAction: (Int) -> Void
    private let loadSucceededAction: (Int) -> Void
    private let loadFailedAction: (Int, URL?) -> Void
    private let copyImageAction: (URL) -> Void
    private let saveImageAction: (URL) -> Void
    private let shareImageAction: (URL) -> Void

    init(
        index: Int, isDualPage: Bool, isDatabaseLoading: Bool, backgroundColor: Color,
        pageModel: ReadingPageModel, enablesLiveText: Bool,
        focusedLiveTextGroup: LiveTextGroup?,
        liveTextTapAction: @escaping (LiveTextGroup) -> Void,
        fetchAction: @escaping (Int) -> Void,
        refetchAction: @escaping (Int) -> Void, prefetchAction: @escaping (Int) -> Void,
        loadRetryAction: @escaping (Int) -> Void, loadSucceededAction: @escaping (Int) -> Void,
        loadFailedAction: @escaping (Int, URL?) -> Void, copyImageAction: @escaping (URL) -> Void,
        saveImageAction: @escaping (URL) -> Void, shareImageAction: @escaping (URL) -> Void
    ) {
        self.index = index
        self.isDualPage = isDualPage
        self.isDatabaseLoading = isDatabaseLoading
        self.backgroundColor = backgroundColor
        self.pageModel = pageModel
        self.enablesLiveText = enablesLiveText
        self.focusedLiveTextGroup = focusedLiveTextGroup
        self.liveTextTapAction = liveTextTapAction
        self.fetchAction = fetchAction
        self.refetchAction = refetchAction
        self.prefetchAction = prefetchAction
        self.loadRetryAction = loadRetryAction
        self.loadSucceededAction = loadSucceededAction
        self.loadFailedAction = loadFailedAction
        self.copyImageAction = copyImageAction
        self.saveImageAction = saveImageAction
        self.shareImageAction = shareImageAction
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.index == rhs.index
            && lhs.isDualPage == rhs.isDualPage
            && lhs.isDatabaseLoading == rhs.isDatabaseLoading
            && lhs.backgroundColor == rhs.backgroundColor
            && lhs.pageModel == rhs.pageModel
            && lhs.enablesLiveText == rhs.enablesLiveText
            && lhs.focusedLiveTextGroup == rhs.focusedLiveTextGroup
    }

    var body: some View {
        HStack(spacing: 0) {
            if let first = pageModel.first {
                imageContainer(model: first)
            }
            if let second = pageModel.second {
                imageContainer(model: second)
            }
        }
        .onAppear(perform: loadPageIfNeeded)
        .onChange(of: isDatabaseLoading) { _, isLoading in
            if !isLoading {
                loadPageIfNeeded()
            }
        }
    }

    func imageContainer(model: ReadingImageModel) -> some View {
        ImageContainer(
            index: model.index,
            imageURL: model.imageURL,
            loadingState: model.loadingState,
            isDualPage: isDualPage,
            backgroundColor: backgroundColor,
            enablesLiveText: enablesLiveText,
            liveTextGroups: model.liveTextGroups,
            focusedLiveTextGroup: focusedLiveTextGroup,
            liveTextTapAction: liveTextTapAction,
            refetchAction: refetchAction,
            loadRetryAction: loadRetryAction,
            loadSucceededAction: loadSucceededAction,
            loadFailedAction: loadFailedAction
        )
        .contextMenu { contextMenuItems(model: model) }
    }

    private func loadPageIfNeeded() {
        guard !isDatabaseLoading else { return }
        for model in pageModel.images where model.imageURL == nil {
            fetchAction(model.index)
        }
        prefetchAction(index)
    }

    @ViewBuilder private func contextMenuItems(model: ReadingImageModel) -> some View {
        if model.imageURL?.isFileURL != true {
            Button {
                refetchAction(model.index)
            } label: {
                Label(
                    L10n.Localizable.ReadingView.ContextMenu.Button.reload,
                    systemSymbol: .arrowCounterclockwise
                )
            }
        }
        if let imageURL = model.imageURL {
            Button {
                copyImageAction(imageURL)
            } label: {
                Label(L10n.Localizable.ReadingView.ContextMenu.Button.copy, systemSymbol: .plusSquareOnSquare)
            }
            Button {
                saveImageAction(imageURL)
            } label: {
                Label(L10n.Localizable.ReadingView.ContextMenu.Button.save, systemSymbol: .squareAndArrowDown)
            }
            if let originalImageURL = model.originalImageURL {
                Button {
                    saveImageAction(originalImageURL)
                } label: {
                    Label(
                        L10n.Localizable.ReadingView.ContextMenu.Button.saveOriginal,
                        systemSymbol: .squareAndArrowDownOnSquare
                    )
                }
            }
            Button {
                shareImageAction(imageURL)
            } label: {
                Label(L10n.Localizable.ReadingView.ContextMenu.Button.share, systemSymbol: .squareAndArrowUp)
            }
        }
    }
}

// MARK: ImageContainer
private struct ImageContainer: View {
    @Environment(\.displayScale) private var displayScale

    private var width: CGFloat {
        DeviceUtil.windowW / (isDualPage ? 2 : 1)
    }
    private var height: CGFloat {
        width / Defaults.ImageSize.contentAspect
    }
    private var targetPixelSize: CGSize {
        ReadingImageSizing.targetPixelSize(
            isDualPage: isDualPage,
            displayScale: displayScale
        )
    }

    private let index: Int
    private let imageURL: URL?
    private let loadingState: LoadingState
    private let isDualPage: Bool
    private let backgroundColor: Color
    private let enablesLiveText: Bool
    private let liveTextGroups: [LiveTextGroup]
    private let focusedLiveTextGroup: LiveTextGroup?
    private let liveTextTapAction: (LiveTextGroup) -> Void
    private let refetchAction: (Int) -> Void
    private let loadRetryAction: (Int) -> Void
    private let loadSucceededAction: (Int) -> Void
    private let loadFailedAction: (Int, URL?) -> Void

    init(
        index: Int, imageURL: URL?,
        loadingState: LoadingState,
        isDualPage: Bool,
        backgroundColor: Color,
        enablesLiveText: Bool,
        liveTextGroups: [LiveTextGroup],
        focusedLiveTextGroup: LiveTextGroup?,
        liveTextTapAction: @escaping (LiveTextGroup) -> Void,
        refetchAction: @escaping (Int) -> Void,
        loadRetryAction: @escaping (Int) -> Void,
        loadSucceededAction: @escaping (Int) -> Void,
        loadFailedAction: @escaping (Int, URL?) -> Void
    ) {
        self.index = index
        self.imageURL = imageURL
        self.loadingState = loadingState
        self.isDualPage = isDualPage
        self.backgroundColor = backgroundColor
        self.enablesLiveText = enablesLiveText
        self.liveTextGroups = liveTextGroups
        self.focusedLiveTextGroup = focusedLiveTextGroup
        self.liveTextTapAction = liveTextTapAction
        self.refetchAction = refetchAction
        self.loadRetryAction = loadRetryAction
        self.loadSucceededAction = loadSucceededAction
        self.loadFailedAction = loadFailedAction
    }

    private func placeholder(_ progress: Progress) -> some View {
        Placeholder(style: .progress(
            pageNumber: index, progress: progress,
            isDualPage: isDualPage, backgroundColor: backgroundColor
        ))
        .frame(width: width, height: height)
    }
    @ViewBuilder private func image(url: URL?) -> some View {
        if url?.isGIF != true {
            KFImage(url)
                .placeholder(placeholder)
                .setProcessor(DownsamplingImageProcessor(size: targetPixelSize))
                .cacheOriginalImage(url?.isFileURL != true)
                .cacheMemoryOnly(url?.isFileURL == true)
                .backgroundDecode()
                .loadDiskFileSynchronously(false)
                .cancelOnDisappear(true)
                .resizable()
                .onSuccess(onSuccess).onFailure(onFailure)
        } else {
            KFAnimatedImage(url)
                .placeholder(placeholder)
                .cacheMemoryOnly(url?.isFileURL == true)
                .backgroundDecode()
                .loadDiskFileSynchronously(false)
                .cancelOnDisappear(true)
                .onSuccess(onSuccess).onFailure(onFailure)
        }
    }

    var body: some View {
        if loadingState == .idle {
            image(url: imageURL)
                .scaledToFit()
                .overlay {
                    if enablesLiveText {
                        LiveTextView(
                            liveTextGroups: liveTextGroups,
                            focusedLiveTextGroup: focusedLiveTextGroup,
                            tapAction: liveTextTapAction
                        )
                    }
                }
        } else {
            ZStack {
                backgroundColor
                VStack {
                    Text(String(index)).font(.largeTitle.bold())
                        .foregroundColor(.gray).padding(.bottom, 30)
                    ZStack {
                        Button(action: reloadImage) {
                            Image(systemSymbol: .exclamationmarkArrowTriangle2Circlepath)
                        }
                        .font(.system(size: 30, weight: .medium)).foregroundColor(.gray)
                        .opacity(loadingState == .loading ? 0 : 1)
                        ProgressView().opacity(loadingState == .loading ? 1 : 0)
                    }
                }
            }
            .frame(width: width, height: height)
        }
    }
    private func reloadImage() {
        if let error = loadingState.failed {
            if case .webImageFailed = error {
                loadRetryAction(index)
            } else {
                refetchAction(index)
            }
        }
    }
    private func onSuccess(_: RetrieveImageResult) {
        loadSucceededAction(index)
    }
    private func onFailure(_: KingfisherError) {
        if imageURL != nil {
            loadFailedAction(index, imageURL)
        }
    }
}

// MARK: Definition
struct ImageStackConfig {
    let firstIndex: Int
    let secondIndex: Int
    let isFirstAvailable: Bool
    let isSecondAvailable: Bool
}

private struct ReadingPageModel: Equatable {
    let first: ReadingImageModel?
    let second: ReadingImageModel?

    var images: [ReadingImageModel] {
        [first, second].compactMap { $0 }
    }
}

private struct ReadingImageModel: Equatable {
    let index: Int
    let imageURL: URL?
    let originalImageURL: URL?
    let loadingState: LoadingState
    let liveTextGroups: [LiveTextGroup]
}

private enum ReadingImageSizing {
    static func targetPixelSize(
        isDualPage: Bool,
        displayScale: CGFloat
    ) -> CGSize {
        let pointWidth = DeviceUtil.windowW / (isDualPage ? 2 : 1)
        let pixelWidth = max(pointWidth * displayScale, 1)
        return .init(
            width: pixelWidth,
            height: pixelWidth / Defaults.ImageSize.contentAspect
        )
    }

    static func processor(
        isDualPage: Bool,
        displayScale: CGFloat
    ) -> DownsamplingImageProcessor {
        .init(size: targetPixelSize(
            isDualPage: isDualPage,
            displayScale: displayScale
        ))
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
