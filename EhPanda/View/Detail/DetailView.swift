//
//  DetailView.swift
//  EhPanda
//

import SwiftUI
import Kingfisher
import ComposableArchitecture
import CommonMark

private enum DetailNavigationRoute: Hashable {
    case previews
    case comments(URL)
    case detailSearch(String)
    case galleryInfos(DetailGalleryInfosDestination)
}

private struct DetailGalleryInfosDestination: Hashable {
    let gallery: Gallery
    let galleryDetail: GalleryDetail

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.gallery.id == rhs.gallery.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(gallery.id)
    }
}

struct DetailView: View {
    @Bindable private var store: StoreOf<DetailReducer>
    private let gid: String
    private let user: User
    @Binding private var setting: Setting
    private let blurRadius: Double
    private let tagTranslator: TagTranslator
    @State private var showsDeleteCacheConfirmation = false

    init(
        store: StoreOf<DetailReducer>, gid: String,
        user: User, setting: Binding<Setting>, blurRadius: Double, tagTranslator: TagTranslator
    ) {
        self.store = store
        self.gid = gid
        self.user = user
        _setting = setting
        self.blurRadius = blurRadius
        self.tagTranslator = tagTranslator
    }

    var content: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    HeaderSection(
                        gallery: store.gallery,
                        galleryDetail: store.galleryDetail ?? .empty,
                        user: user,
                        displaysJapaneseTitle: setting.displaysJapaneseTitle,
                        showFullTitle: store.showsFullTitle,
                        showFullTitleAction: { store.send(.toggleShowFullTitle) },
                        favorAction: { store.send(.favorGallery($0)) },
                        unfavorAction: { store.send(.unfavorGallery) },
                        navigateReadingAction: { store.send(.setNavigation(.reading())) },
                        cacheItem: store.cacheItem,
                        navigateUploaderAction: {
                            if let uploader = store.galleryDetail?.uploader {
                                let keyword = "uploader:" + "\"\(uploader)\""
                                store.send(.setNavigation(.detailSearch(keyword)))
                            }
                        }
                    )
                    .padding(.horizontal)
                    DescriptionSection(
                        gallery: store.gallery,
                        galleryDetail: store.galleryDetail ?? .empty,
                        navigateGalleryInfosAction: {
                            if let galleryDetail = store.galleryDetail {
                                store.send(.setNavigation(.galleryInfos(store.gallery, galleryDetail)))
                            }
                        }
                    )
                    ActionSection(
                        galleryDetail: store.galleryDetail ?? .empty,
                        userRating: store.userRating,
                        showUserRating: store.showsUserRating,
                        showUserRatingAction: { store.send(.toggleShowUserRating) },
                        updateRatingAction: { store.send(.updateRating($0)) },
                        confirmRatingAction: { store.send(.confirmRating($0)) },
                        navigateSimilarGalleryAction: {
                            if let trimmedTitle = store.galleryDetail?.trimmedTitle {
                                store.send(.setNavigation(.detailSearch(trimmedTitle)))
                            }
                        }
                    )
                    if !store.galleryTags.isEmpty {
                        TagsSection(
                            tags: store.galleryTags, showsImages: setting.showsImagesInTags,
                            voteTagAction: { store.send(.voteTag($0, $1)) },
                            navigateSearchAction: { store.send(.setNavigation(.detailSearch($0))) },
                            navigateTagDetailAction: { store.send(.setNavigation(.tagDetail($0))) },
                            translateAction: { tagTranslator.lookup(word: $0, returnOriginal: !setting.translatesTags) }
                        )
                    }
                    if !store.galleryPreviewURLs.isEmpty {
                        PreviewsSection(
                            pageCount: store.galleryDetail?.pageCount ?? 0,
                            previewURLs: store.galleryPreviewURLs,
                            navigatePreviewsAction: { store.send(.setNavigation(.previews)) },
                            navigateReadingAction: {
                                store.send(.updateReadingProgress($0))
                                store.send(.setNavigation(.reading()))
                            }
                        )
                    }
                    CommentsSection(
                        comments: store.galleryComments,
                        navigateCommentAction: {
                            if let galleryURL = store.gallery.galleryURL {
                                store.send(.setNavigation(.comments(galleryURL)))
                            }
                        },
                        navigatePostCommentAction: { store.send(.setNavigation(.postComment())) }
                    )
                }
            }
            .contentMargins(.top, 16, for: .scrollContent)
            .contentMargins(.bottom, 20, for: .scrollContent)
            .opacity(store.galleryDetail == nil ? 0 : 1)

            LoadingView()
                .opacity(
                    store.galleryDetail == nil
                    && store.loadingState == .loading ? 1 : 0
                )

            let error = store.loadingState.failed
            let retryAction: () -> Void = { store.send(.fetchGalleryDetail) }
            ErrorView(error: error ?? .unknown, action: error?.isRetryable != false ? retryAction : nil)
                .opacity(store.galleryDetail == nil && error != nil ? 1 : 0)
        }
    }

    func modalModifiers<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .fullScreenCover(item: $store.route.sending(\.setNavigation).reading) { _ in
                ReadingView(
                    store: store.scope(state: \.readingState, action: \.reading),
                    gid: gid,
                    setting: $setting,
                    blurRadius: blurRadius
                )
                .accentColor(setting.accentColor)
                .autoBlur(radius: blurRadius)
            }
            .sheet(item: $store.route.sending(\.setNavigation).archives, id: \.0.absoluteString) { urls in
                let (galleryURL, archiveURL) = urls
                ArchivesView(
                    store: store.scope(state: \.archivesState, action: \.archives),
                    gid: gid,
                    user: user,
                    galleryURL: galleryURL,
                    archiveURL: archiveURL
                )
                .accentColor(setting.accentColor)
                .autoBlur(radius: blurRadius)
            }
            .sheet(item: $store.route.sending(\.setNavigation).torrents) { _ in
                TorrentsView(
                    store: store.scope(state: \.torrentsState, action: \.torrents),
                    gid: gid,
                    token: store.gallery.token,
                    blurRadius: blurRadius
                )
                .accentColor(setting.accentColor)
                .autoBlur(radius: blurRadius)
            }
            .sheet(item: $store.route.sending(\.setNavigation).share, id: \.absoluteString) { url in
                ActivityView(activityItems: [url])
                    .autoBlur(radius: blurRadius)
            }
            .sheet(item: $store.route.sending(\.setNavigation).postComment) { _ in
                PostCommentView(
                    title: L10n.Localizable.PostCommentView.Title.postComment,
                    content: $store.commentContent,
                    isFocused: $store.postCommentFocused,
                    postAction: {
                        if let galleryURL = store.gallery.galleryURL {
                            store.send(.postComment(galleryURL))
                        }
                        store.send(.setNavigation(nil))
                    },
                    cancelAction: { store.send(.setNavigation(nil)) },
                    onAppearAction: { store.send(.onPostCommentAppear) }
                )
                .accentColor(setting.accentColor)
                .autoBlur(radius: blurRadius)
            }
            .sheet(item: $store.route.sending(\.setNavigation).newDawn) { greeting in
                NewDawnView(greeting: greeting)
                    .autoBlur(radius: blurRadius)
            }
            .sheet(item: $store.route.sending(\.setNavigation).tagDetail, id: \.title) { detail in
                TagDetailView(detail: detail)
                    .autoBlur(radius: blurRadius)
            }
    }

    var body: some View {
        modalModifiers(content: { content })
            .animation(.default, value: store.showsUserRating)
            .animation(.default, value: store.showsFullTitle)
            .animation(.default, value: store.galleryDetail)
            .onAppear {
                DispatchQueue.main.async {
                    store.send(.onAppear(gid, setting.showsNewDawnGreeting))
                }
            }
            .navigationDestination(item: navigationRoute) { route in
                navigationDestination(for: route)
            }
            .toolbar(content: toolbar)
            .confirmationDialog(
                L10n.Localizable.DetailView.Cache.Confirmation.Delete.title,
                isPresented: $showsDeleteCacheConfirmation,
                titleVisibility: .visible
            ) {
                Button(
                    L10n.Localizable.CacheView.Button.delete,
                    role: .destructive
                ) {
                    store.send(.deleteCache)
                }
            } message: {
                Text(L10n.Localizable.DetailView.Cache.Confirmation.Delete.message)
            }
    }
}

// MARK: Navigation
private extension DetailView {
    var navigationRoute: Binding<DetailNavigationRoute?> {
        Binding(
            get: {
                switch store.route {
                case .previews:
                    return .previews
                case .comments(let url):
                    return .comments(url)
                case .detailSearch(let keyword):
                    return .detailSearch(keyword)
                case .galleryInfos(let gallery, let galleryDetail):
                    return .galleryInfos(.init(gallery: gallery, galleryDetail: galleryDetail))
                default:
                    return nil
                }
            },
            set: { route in
                guard let route else {
                    store.send(.setNavigation(nil))
                    return
                }
                switch route {
                case .previews:
                    store.send(.setNavigation(.previews))
                case .comments(let url):
                    store.send(.setNavigation(.comments(url)))
                case .detailSearch(let keyword):
                    store.send(.setNavigation(.detailSearch(keyword)))
                case .galleryInfos(let destination):
                    store.send(.setNavigation(.galleryInfos(
                        destination.gallery,
                        destination.galleryDetail
                    )))
                }
            }
        )
    }

    @ViewBuilder func navigationDestination(for route: DetailNavigationRoute) -> some View {
        switch route {
        case .previews:
            PreviewsView(
                store: store.scope(state: \.previewsState, action: \.previews),
                gid: gid, setting: $setting, blurRadius: blurRadius
            )
        case .comments(let galleryURL):
            if let commentStore = store.scope(state: \.commentsState.wrappedValue, action: \.comments) {
                CommentsView(
                    store: commentStore, gid: gid, token: store.gallery.token, apiKey: store.apiKey,
                    galleryURL: galleryURL, comments: store.galleryComments, user: user,
                    setting: $setting, blurRadius: blurRadius,
                    tagTranslator: tagTranslator
                )
            }
        case .detailSearch(let keyword):
            if let detailSearchStore = store.scope(state: \.detailSearchState.wrappedValue, action: \.detailSearch) {
                DetailSearchView(
                    store: detailSearchStore, keyword: keyword, user: user, setting: $setting,
                    blurRadius: blurRadius, tagTranslator: tagTranslator
                )
            }
        case .galleryInfos(let destination):
            GalleryInfosView(
                store: store.scope(state: \.galleryInfosState, action: \.galleryInfos),
                gallery: destination.gallery,
                galleryDetail: destination.galleryDetail
            )
        }
    }
}

// MARK: ToolBar
private extension DetailView {
    func toolbar() -> some ToolbarContent {
        CustomToolbarItem {
            ToolbarFeaturesMenu {
                cacheMenuItems
                Divider()
                Button {
                    if let galleryURL = store.gallery.galleryURL,
                       let archiveURL = store.galleryDetail?.archiveURL
                    {
                        store.send(.setNavigation(.archives(galleryURL, archiveURL)))
                    }
                } label: {
                    Label(L10n.Localizable.DetailView.ToolbarItem.Button.archives, systemSymbol: .docZipper)
                }
                .disabled(store.galleryDetail?.archiveURL == nil || !CookieUtil.didLogin)
                Button {
                    store.send(.setNavigation(.torrents()))
                } label: {
                    let base = L10n.Localizable.DetailView.ToolbarItem.Button.torrents
                    let torrentCount = store.galleryDetail?.torrentCount ?? 0
                    let baseWithCount = [base, "(\(torrentCount))"].joined(separator: " ")
                    Label(torrentCount > 0 ? baseWithCount : base, systemSymbol: .leaf)
                }
                .disabled((store.galleryDetail?.torrentCount ?? 0 > 0) != true)
                Button {
                    if let galleryURL = store.gallery.galleryURL {
                        store.send(.setNavigation(.share(galleryURL)))
                    }
                } label: {
                    Label(L10n.Localizable.DetailView.ToolbarItem.Button.share, systemSymbol: .squareAndArrowUp)
                }
            }
            .disabled(store.galleryDetail == nil)
        }
    }

    @ViewBuilder
    private var cacheMenuItems: some View {
        if let cacheItem = store.cacheItem {
            if cacheItem.status.isActive {
                Button {
                    store.send(.pauseCache)
                } label: {
                    Label(
                        L10n.Localizable.CacheView.Button.pause,
                        systemImage: "pause.circle"
                    )
                }
            } else if !cacheItem.isComplete {
                Button {
                    store.send(.resumeCache(.init(setting: setting)))
                } label: {
                    Label(
                        cacheItem.status == .failed
                            ? L10n.Localizable.CacheView.Button.retry
                            : L10n.Localizable.CacheView.Button.resume,
                        systemImage: cacheItem.status == .failed
                            ? "arrow.clockwise"
                            : "play.circle"
                    )
                }
            } else {
                Label(
                    L10n.Localizable.DetailView.Cache.Status.cached,
                    systemImage: "checkmark.circle.fill"
                )
            }

            Button(role: .destructive) {
                showsDeleteCacheConfirmation = true
            } label: {
                Label(
                    L10n.Localizable.DetailView.Cache.Button.remove,
                    systemImage: "trash"
                )
            }
        } else {
            Button {
                store.send(.enqueueCache(.init(setting: setting)))
            } label: {
                Label(
                    L10n.Localizable.DetailView.Cache.Button.cache,
                    systemImage: "square.and.arrow.down"
                )
            }
        }
    }
}

// MARK: HeaderSection
private struct HeaderSection: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let gallery: Gallery
    private let galleryDetail: GalleryDetail
    private let user: User
    private let displaysJapaneseTitle: Bool
    private let showFullTitle: Bool
    private let showFullTitleAction: () -> Void
    private let favorAction: (Int) -> Void
    private let unfavorAction: () -> Void
    private let navigateReadingAction: () -> Void
    private let cacheItem: GalleryCacheItem?
    private let navigateUploaderAction: () -> Void

    init(
        gallery: Gallery, galleryDetail: GalleryDetail,
        user: User, displaysJapaneseTitle: Bool, showFullTitle: Bool,
        showFullTitleAction: @escaping () -> Void,
        favorAction: @escaping (Int) -> Void,
        unfavorAction: @escaping () -> Void,
        navigateReadingAction: @escaping () -> Void,
        cacheItem: GalleryCacheItem?,
        navigateUploaderAction: @escaping () -> Void
    ) {
        self.gallery = gallery
        self.galleryDetail = galleryDetail
        self.user = user
        self.displaysJapaneseTitle = displaysJapaneseTitle
        self.showFullTitle = showFullTitle
        self.showFullTitleAction = showFullTitleAction
        self.favorAction = favorAction
        self.unfavorAction = unfavorAction
        self.navigateReadingAction = navigateReadingAction
        self.cacheItem = cacheItem
        self.navigateUploaderAction = navigateUploaderAction
    }

    private var title: String {
        let normalTitle = galleryDetail.title
        return displaysJapaneseTitle ? galleryDetail.jpnTitle ?? normalTitle : normalTitle
    }

    private var cover: some View {
        KFImage(cacheItem?.coverFileURL ?? gallery.coverURL)
            .placeholder({ Placeholder(style: .activity(ratio: Defaults.ImageSize.headerAspect)) })
            .defaultModifier()
            .scaledToFit()
            .frame(
                width: Defaults.ImageSize.headerW,
                height: Defaults.ImageSize.headerH
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: showFullTitleAction) {
                Text(title)
                    .font(.title3.bold())
                    .multilineTextAlignment(.leading)
                    .tint(.primary)
                    .lineLimit(showFullTitle ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)

            Button(gallery.uploader ?? "", action: navigateUploaderAction)
                .lineLimit(1)
                .font(.callout)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)

            if let cacheItem {
                Label(
                    cacheItem.isComplete
                        ? L10n.Localizable.DetailView.Cache.Status.cached
                        : cacheItem.status.value,
                    systemImage: cacheItem.isComplete
                        ? "checkmark.circle.fill"
                        : "arrow.down.circle"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(cacheItem.isComplete ? .green : .secondary)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            CategoryLabel(
                text: gallery.category.value,
                color: gallery.color,
                font: .headline,
                insets: .init(top: 2, leading: 4, bottom: 2, trailing: 4),
                cornerRadius: 3
            )

            Spacer(minLength: 8)

            Group {
                if galleryDetail.isFavorited {
                    Button(action: unfavorAction) {
                        Image(systemSymbol: .heartFill)
                    }
                } else {
                    Menu {
                        ForEach(0..<10) { index in
                            Button(user.getFavoriteCategory(index: index)) {
                                favorAction(index)
                            }
                        }
                    } label: {
                        Image(systemSymbol: .heart)
                    }
                }
            }
            .imageScale(.large)
            .foregroundStyle(.tint)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .disabled(!CookieUtil.didLogin)

            Button(action: navigateReadingAction) {
                Text(L10n.Localizable.DetailView.Button.read)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
        .minimumScaleFactor(0.75)
    }

    private var regularHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            cover

            VStack(alignment: .leading, spacing: 8) {
                titleBlock
                Spacer(minLength: 8)
                actionRow
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(minWidth: 190, alignment: .leading)
            .frame(minHeight: Defaults.ImageSize.headerH, alignment: .leading)
        }
    }

    private var compactHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                cover
                titleBlock
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            actionRow
        }
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            compactHeader
        } else {
            ViewThatFits(in: .horizontal) {
                regularHeader
                compactHeader
            }
        }
    }
}

// MARK: DescriptionSection
private struct DescriptionSection: View {
    private let gallery: Gallery
    private let galleryDetail: GalleryDetail
    private let navigateGalleryInfosAction: () -> Void

    init(
        gallery: Gallery, galleryDetail: GalleryDetail,
        navigateGalleryInfosAction: @escaping () -> Void
    ) {
        self.gallery = gallery
        self.galleryDetail = galleryDetail
        self.navigateGalleryInfosAction = navigateGalleryInfosAction
    }

    private var infos: [DescScrollInfo] {[
        DescScrollInfo(
            title: L10n.Localizable.DetailView.DescriptionSection.Title.favorited,
            description: L10n.Localizable.DetailView.DescriptionSection.Description.favorited,
            value: .init(galleryDetail.favoritedCount)
        ),
        DescScrollInfo(
            title: L10n.Localizable.DetailView.DescriptionSection.Title.language,
            description: galleryDetail.language.value,
            value: galleryDetail.language.abbreviation
        ),
        DescScrollInfo(
            title: L10n.Localizable.DetailView.DescriptionSection.Title.ratings("\(galleryDetail.ratingCount)"),
            description: .init(), value: .init(), rating: galleryDetail.rating, isRating: true
        ),
        DescScrollInfo(
            title: L10n.Localizable.DetailView.DescriptionSection.Title.pageCount,
            description: L10n.Localizable.DetailView.DescriptionSection.Description.pageCount,
            value: .init(galleryDetail.pageCount)
        ),
        DescScrollInfo(
            title: L10n.Localizable.DetailView.DescriptionSection.Title.fileSize,
            description: galleryDetail.sizeType, value: .init(galleryDetail.sizeCount)
        )
    ]}
    private var itemWidth: Double {
        max(DeviceUtil.absWindowW / 5, 80)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(infos) { info in
                    Group {
                        if info.isRating {
                            DescScrollRatingItem(title: info.title, rating: info.rating)
                        } else {
                            DescScrollItem(title: info.title, value: info.value, description: info.description)
                        }
                    }
                    .frame(width: itemWidth)
                    Divider()
                        .frame(height: 40)
                    if info == infos.last {
                        Button(action: navigateGalleryInfosAction) {
                            Image(systemSymbol: .ellipsis)
                                .font(.system(size: 20, weight: .bold))
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .frame(width: itemWidth)
                    }
                }
            }
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .frame(minHeight: 64)
    }
}

private extension DescriptionSection {
    struct DescScrollInfo: Identifiable, Equatable {
        var id: String { title }

        let title: String
        let description: String
        let value: String
        var rating: Float = 0
        var isRating = false
    }
    struct DescScrollItem: View {
        private let title: String
        private let value: String
        private let description: String

        init(title: String, value: String, description: String) {
            self.title = title
            self.value = value
            self.description = description
        }

        var body: some View {
            VStack(spacing: 3) {
                Text(title).textCase(.uppercase).font(.caption)
                Text(value).fontWeight(.medium).font(.title3).lineLimit(1)
                Text(description).font(.caption)
            }
        }
    }
    struct DescScrollRatingItem: View {
        private let title: String
        private let rating: Float

        init(title: String, rating: Float) {
            self.title = title
            self.rating = rating
        }

        var body: some View {
            VStack(spacing: 3) {
                Text(title).textCase(.uppercase).font(.caption).lineLimit(1)
                Text(String(format: "%.2f", rating)).fontWeight(.medium).font(.title3)
                RatingView(rating: rating).font(.system(size: 12)).foregroundStyle(.primary)
            }
        }
    }
}

// MARK: ActionSection
private struct ActionSection: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let galleryDetail: GalleryDetail
    private let userRating: Int
    private let showUserRating: Bool
    private let showUserRatingAction: () -> Void
    private let updateRatingAction: (DragGesture.Value) -> Void
    private let confirmRatingAction: (DragGesture.Value) -> Void
    private let navigateSimilarGalleryAction: () -> Void

    init(
        galleryDetail: GalleryDetail,
        userRating: Int, showUserRating: Bool,
        showUserRatingAction: @escaping () -> Void,
        updateRatingAction: @escaping (DragGesture.Value) -> Void,
        confirmRatingAction: @escaping (DragGesture.Value) -> Void,
        navigateSimilarGalleryAction: @escaping () -> Void
    ) {
        self.galleryDetail = galleryDetail
        self.userRating = userRating
        self.showUserRating = showUserRating
        self.showUserRatingAction = showUserRatingAction
        self.updateRatingAction = updateRatingAction
        self.confirmRatingAction = confirmRatingAction
        self.navigateSimilarGalleryAction = navigateSimilarGalleryAction
    }

    private var ratingButton: some View {
        Button(action: showUserRatingAction) {
            Label(
                L10n.Localizable.DetailView.ActionSection.Button.giveARating,
                systemSymbol: .squareAndPencil
            )
            .font(.callout.weight(.semibold))
            .frame(maxWidth: .infinity)
        }
        .disabled(!CookieUtil.didLogin)
    }

    private var similarButton: some View {
        Button(action: navigateSimilarGalleryAction) {
            Label(
                L10n.Localizable.DetailView.ActionSection.Button.similarGallery,
                systemSymbol: .photoOnRectangleAngled
            )
            .font(.callout.weight(.semibold))
            .frame(maxWidth: .infinity)
        }
    }

    private var verticalActions: some View {
        VStack(spacing: 10) {
            ratingButton
            similarButton
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    verticalActions
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            ratingButton
                                .fixedSize(horizontal: true, vertical: false)
                            similarButton
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        verticalActions
                    }
                }
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.large)

            if showUserRating {
                RatingView(rating: Float(userRating) / 2)
                    .font(.system(size: 24))
                    .foregroundStyle(.yellow)
                    .padding(.vertical, 8)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged(updateRatingAction)
                            .onEnded(confirmRatingAction)
                    )
            }
        }
        .padding(.horizontal)
    }
}

// MARK: TagsSection
private struct TagsSection: View {
    private let tags: [GalleryTag]
    private let showsImages: Bool
    private let voteTagAction: (String, Int) -> Void
    private let navigateSearchAction: (String) -> Void
    private let navigateTagDetailAction: (TagDetail) -> Void
    private let translateAction: (String) -> (String, TagTranslation?)

    init(
        tags: [GalleryTag], showsImages: Bool,
        voteTagAction: @escaping (String, Int) -> Void,
        navigateSearchAction: @escaping (String) -> Void,
        navigateTagDetailAction: @escaping (TagDetail) -> Void,
        translateAction: @escaping (String) -> (String, TagTranslation?)
    ) {
        self.tags = tags
        self.showsImages = showsImages
        self.voteTagAction = voteTagAction
        self.navigateSearchAction = navigateSearchAction
        self.navigateTagDetailAction = navigateTagDetailAction
        self.translateAction = translateAction
    }

    var body: some View {
        VStack(alignment: .leading) {
            ForEach(tags) { tag in
                TagRow(
                    tag: tag, showsImages: showsImages,
                    voteTagAction: voteTagAction,
                    navigateSearchAction: navigateSearchAction,
                    navigateTagDetailAction: navigateTagDetailAction,
                    translateAction: translateAction
                )
            }
        }
        .padding(.horizontal)
    }
}

private extension TagsSection {
    struct TagRow: View {
        private let tag: GalleryTag
        private let showsImages: Bool
        private let voteTagAction: (String, Int) -> Void
        private let navigateSearchAction: (String) -> Void
        private let navigateTagDetailAction: (TagDetail) -> Void
        private let translateAction: (String) -> (String, TagTranslation?)

        init(
            tag: GalleryTag, showsImages: Bool,
            voteTagAction: @escaping (String, Int) -> Void,
            navigateSearchAction: @escaping (String) -> Void,
            navigateTagDetailAction: @escaping (TagDetail) -> Void,
            translateAction: @escaping (String) -> (String, TagTranslation?)
        ) {
            self.tag = tag
            self.showsImages = showsImages
            self.voteTagAction = voteTagAction
            self.navigateSearchAction = navigateSearchAction
            self.navigateTagDetailAction = navigateTagDetailAction
            self.translateAction = translateAction
        }

        private var backgroundColor: Color {
            Color(.tertiarySystemFill)
        }
        private var padding: EdgeInsets {
            .init(top: 5, leading: 14, bottom: 5, trailing: 14)
        }

        var body: some View {
            HStack(alignment: .top) {
                Text(tag.namespace?.value ?? tag.rawNamespace).font(.subheadline.bold())
                    .foregroundStyle(.primary)
                    .padding(padding)
                    .background(
                        Color(.secondarySystemFill),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
                TagCloudView(data: tag.contents) { content in
                    let (_, translation) = translateAction(content.rawNamespace + content.text)
                    Button {
                        navigateSearchAction(content.serachKeyword(tag: tag))
                    } label: {
                        TagCloudCell(
                            text: translation?.displayValue ?? content.text,
                            imageURL: translation?.valueImageURL,
                            showsImages: showsImages,
                            font: .subheadline, padding: padding, textColor: .primary,
                            backgroundColor: backgroundColor
                        )
                    }
                    .contextMenu {
                        if let translation = translation,
                            let description = translation.descriptionPlainText,
                            !description.isEmpty
                        {
                            Button {
                                navigateTagDetailAction(.init(
                                    title: translation.displayValue, description: description,
                                    imageURLs: translation.descriptionImageURLs,
                                    links: translation.links
                                ))
                            } label: {
                                Image(systemSymbol: .docRichtext)
                                Text(L10n.Localizable.DetailView.ContextMenu.Button.detail)
                            }
                        }
                        if CookieUtil.didLogin {
                            if content.isVotedUp || content.isVotedDown {
                                Button {
                                    voteTagAction(content.voteKeyword(tag: tag), content.isVotedUp ? -1 : 1)
                                } label: {
                                    Image(systemSymbol: content.isVotedUp ? .handThumbsup : .handThumbsdown)
                                        .symbolVariant(.fill)
                                    Text(L10n.Localizable.DetailView.ContextMenu.Button.withdrawVote)
                                }
                            } else {
                                Button {
                                    voteTagAction(content.voteKeyword(tag: tag), 1)
                                } label: {
                                    Image(systemSymbol: .handThumbsup)
                                    Text(L10n.Localizable.DetailView.ContextMenu.Button.voteUp)
                                }
                                Button {
                                    voteTagAction(content.voteKeyword(tag: tag), -1)
                                } label: {
                                    Image(systemSymbol: .handThumbsdown)
                                    Text(L10n.Localizable.DetailView.ContextMenu.Button.voteDown)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: PreviewSection
private struct PreviewsSection: View {
    @Environment(\.displayScale) private var displayScale

    private let pageCount: Int
    private let previewURLs: [Int: URL]
    private let navigatePreviewsAction: () -> Void
    private let navigateReadingAction: (Int) -> Void

    init(
        pageCount: Int, previewURLs: [Int: URL],
        navigatePreviewsAction: @escaping () -> Void,
        navigateReadingAction: @escaping (Int) -> Void
    ) {
        self.pageCount = pageCount
        self.previewURLs = previewURLs
        self.navigatePreviewsAction = navigatePreviewsAction
        self.navigateReadingAction = navigateReadingAction
    }

    private var width: CGFloat {
        Defaults.ImageSize.previewAvgW
    }
    private var height: CGFloat {
        width / Defaults.ImageSize.previewAspect
    }

    var body: some View {
        SubSection(
            title: L10n.Localizable.DetailView.Section.Title.previews,
            showAll: pageCount > 20, showAllAction: navigatePreviewsAction
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(previewURLs.tuples.sorted(by: { $0.0 < $1.0 }), id: \.0) { index, previewURL in
                        let resource = PreviewResolver.resolve(originalURL: previewURL)
                        Button {
                            navigateReadingAction(index)
                        } label: {
                            KFImage.url(resource.sourceURL)
                                .placeholder { Placeholder(style: .activity(ratio: resource.aspectRatio)) }
                                .setProcessor(resource.processor(targetPixelSize: .init(
                                    width: width * displayScale,
                                    height: height * displayScale
                                )))
                                .cacheOriginalImage()
                                .backgroundDecode()
                                .loadDiskFileSynchronously(false)
                                .cancelOnDisappear(true)
                                .resizable()
                                .scaledToFit()
                                .frame(width: width, height: height)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .id(previewURL.absoluteString)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
        }
    }
}

// MARK: CommentsSection
private struct CommentsSection: View {
    private let comments: [GalleryComment]
    private let navigateCommentAction: () -> Void
    private let navigatePostCommentAction: () -> Void

    init(
        comments: [GalleryComment],
        navigateCommentAction: @escaping () -> Void,
        navigatePostCommentAction: @escaping () -> Void
    ) {
        self.comments = comments
        self.navigateCommentAction = navigateCommentAction
        self.navigatePostCommentAction = navigatePostCommentAction
    }

    var body: some View {
        SubSection(
            title: L10n.Localizable.DetailView.Section.Title.comments,
            showAll: !comments.isEmpty, showAllAction: navigateCommentAction
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(comments.prefix(min(comments.count, 6))) { comment in
                        CommentCell(comment: comment)
                    }
                }
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)

            CommentButton(action: navigatePostCommentAction)
                .padding(.horizontal)
                .disabled(!CookieUtil.didLogin)
        }
    }
}

private struct CommentCell: View {
    private let comment: GalleryComment

    init(comment: GalleryComment) {
        self.comment = comment
    }

    private var content: String {
        comment.contents
            .filter({ [.plainText, .linkedText].contains($0.type) })
            .compactMap(\.text).joined()
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(comment.author).font(.subheadline.bold())
                Spacer()
                Group {
                    ZStack {
                        Image(systemSymbol: .handThumbsupFill)
                            .opacity(comment.votedUp ? 1 : 0)
                        Image(systemSymbol: .handThumbsdownFill)
                            .opacity(comment.votedDown ? 1 : 0)
                    }
                    Text(comment.score ?? "")
                    Text(comment.formattedDateString).lineLimit(1)
                }
                .font(.footnote).foregroundStyle(.secondary)
            }
            .minimumScaleFactor(0.75).lineLimit(1)
            Text(content)
                .lineLimit(3)
                .padding(.top, 1)
            Spacer()
        }
        .padding(14)
        .frame(width: 300, alignment: .topLeading)
        .frame(minHeight: 120, alignment: .topLeading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }
}

private struct CommentButton: View {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(L10n.Localizable.DetailView.Button.postComment, systemSymbol: .squareAndPencil)
                .font(.headline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }
}

struct DetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            DetailView(
                store: .init(initialState: .init(), reducer: DetailReducer.init),
                gid: .init(),
                user: .init(),
                setting: .constant(.init()),
                blurRadius: 0,
                tagTranslator: .init()
            )
        }
    }
}
