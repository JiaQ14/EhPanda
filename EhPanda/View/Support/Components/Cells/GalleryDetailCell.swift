//
//  GalleryDetailCell.swift
//  EhPanda
//

import SwiftUI
import Kingfisher
import ComposableArchitecture

struct GalleryListPresentation: Equatable {
    let coverURL: URL?
    let status: GalleryListStatus?
    let actionRevision: AnyHashable?

    init(
        coverURL: URL?,
        status: GalleryListStatus?,
        actionRevision: AnyHashable? = nil
    ) {
        self.coverURL = coverURL
        self.status = status
        self.actionRevision = actionRevision
    }
}

struct GalleryListStatus: Equatable {
    let text: String
    let detailText: String?
    let message: String?
    let systemImage: String
    let tone: GalleryListStatusTone
    let progress: Double?
}

enum GalleryListStatusTone: Equatable {
    case accent
    case success
    case warning
    case failure
    case secondary

    var color: Color {
        switch self {
        case .accent:
            return .accentColor
        case .success:
            return .green
        case .warning:
            return .orange
        case .failure:
            return .red
        case .secondary:
            return .secondary
        }
    }
}

struct GalleryListAction {
    enum Role: Equatable {
        case normal
        case destructive

        var buttonRole: ButtonRole? {
            self == .destructive ? .destructive : nil
        }
    }

    enum Edge: Equatable {
        case leading
        case trailing
    }

    enum Tint {
        case accent
        case orange
        case green
        case red

        var color: Color {
            switch self {
            case .accent:
                return .accentColor
            case .orange:
                return .orange
            case .green:
                return .green
            case .red:
                return .red
            }
        }
    }

    let title: String
    let systemImage: String
    let role: Role
    let edge: Edge
    let tint: Tint
    let action: () -> Void
}

enum GalleryContextMenuMode {
    case standard
    case downloadsOnly
}

struct GalleryContextMenuConfiguration {
    let mode: GalleryContextMenuMode
    let user: User
    let setting: Setting
    let blurRadius: Double
    let tagTranslator: TagTranslator
    let defaultFavoriteState: Bool?

    static func standard(
        user: User,
        setting: Setting,
        blurRadius: Double,
        tagTranslator: TagTranslator,
        defaultFavoriteState: Bool? = nil
    ) -> Self {
        .init(
            mode: .standard,
            user: user,
            setting: setting,
            blurRadius: blurRadius,
            tagTranslator: tagTranslator,
            defaultFavoriteState: defaultFavoriteState
        )
    }

    static func downloadsOnly(
        user: User,
        setting: Setting,
        blurRadius: Double,
        tagTranslator: TagTranslator
    ) -> Self {
        .init(
            mode: .downloadsOnly,
            user: user,
            setting: setting,
            blurRadius: blurRadius,
            tagTranslator: tagTranslator,
            defaultFavoriteState: nil
        )
    }
}

private struct GalleryContextMenuConfigurationKey: EnvironmentKey {
    static let defaultValue: GalleryContextMenuConfiguration? = nil
}

extension EnvironmentValues {
    var galleryContextMenuConfiguration: GalleryContextMenuConfiguration? {
        get { self[GalleryContextMenuConfigurationKey.self] }
        set { self[GalleryContextMenuConfigurationKey.self] = newValue }
    }
}

extension View {
    func galleryContextMenu(
        gallery: Gallery,
        actions: [GalleryListAction] = [],
        isFavorited: Bool? = nil
    ) -> some View {
        modifier(
            GalleryContextMenuModifier(
                gallery: gallery,
                actions: actions,
                isFavorited: isFavorited
            )
        )
    }
}

private struct GalleryContextMenuModifier: ViewModifier {
    @Environment(\.galleryContextMenuConfiguration) private var configuration
    @State private var presentationRevision = 0

    let gallery: Gallery
    let actions: [GalleryListAction]
    let isFavorited: Bool?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let configuration {
            content
                .contextMenu {
                    switch configuration.mode {
                    case .standard:
                        GalleryStandardContextMenu(
                            gallery: gallery,
                            user: configuration.user,
                            setting: configuration.setting,
                            isFavorited: isFavorited ?? configuration.defaultFavoriteState
                        )
                    case .downloadsOnly:
                        GalleryDownloadContextMenu(actions: actions)
                    }
                } preview: {
                    GalleryDetailContextPreview(
                        gallery: gallery,
                        configuration: configuration
                    )
                    .onDisappear {
                        presentationRevision &+= 1
                    }
                }
                .id(presentationRevision)
                .modifier(
                    GalleryDraggableModifier(
                        gid: gallery.id,
                        url: gallery.galleryURL
                    )
                )
        } else {
            content.modifier(
                GalleryDraggableModifier(
                    gid: gallery.id,
                    url: gallery.galleryURL
                )
            )
        }
    }
}

private struct GalleryDraggableModifier: ViewModifier {
    let gid: String
    let url: URL?

    @ViewBuilder
    func body(content: Content) -> some View {
        if DeviceUtil.isPad {
            content.onDrag {
                GallerySceneActivity.itemProvider(gid: gid, url: url)
            }
        } else {
            content
        }
    }
}

private struct GalleryDownloadContextMenu: View {
    let actions: [GalleryListAction]

    var body: some View {
        ForEach(actions.indices, id: \.self) { index in
            let item = actions[index]
            Button(role: item.role.buttonRole, action: item.action) {
                Label(item.title, systemImage: item.systemImage)
            }
        }
    }
}

private struct GalleryStandardContextMenu: View {
    @Environment(\.isStandaloneGalleryWindow)
    private var isStandaloneGalleryWindow
    @Dependency(\.databaseClient) private var databaseClient
    @Dependency(\.cacheClient) private var cacheClient
    @Dependency(\.hapticsClient) private var hapticsClient

    let gallery: Gallery
    let user: User
    let setting: Setting
    let isFavorited: Bool?

    @State private var favoriteOverride: Bool?
    @State private var operationInProgress = false

    private var galleryIsFavorited: Bool {
        favoriteOverride
            ?? isFavorited
            ?? databaseClient.fetchGalleryDetail(gid: gallery.id)?.isFavorited
            ?? false
    }

    var body: some View {
        Group {
            if DeviceUtil.isPad && !isStandaloneGalleryWindow {
                Button {
                    GallerySceneActivity.openWindow(
                        gid: gallery.id,
                        title: gallery.title
                    )
                } label: {
                    Label(
                        L10n.Localizable.openInNewWindow,
                        systemImage: "macwindow.badge.plus"
                    )
                }
            }

            if galleryIsFavorited {
                Button(role: .destructive) {
                    performUnfavorite()
                } label: {
                    Label(
                        L10n.Localizable.DetailView.ContextMenu.Button.unfavorite,
                        systemImage: "heart.slash"
                    )
                }
            } else {
                Menu {
                    ForEach(0..<10) { index in
                        Button(user.getFavoriteCategory(index: index)) {
                            performFavorite(index: index)
                        }
                    }
                } label: {
                    Label(
                        L10n.Localizable.FavoritesView.Title.favorites,
                        systemImage: "heart"
                    )
                }
                .disabled(!CookieUtil.didLogin)
            }

            Button {
                performCache()
            } label: {
                Label(
                    L10n.Localizable.DetailView.Cache.Button.cache,
                    systemImage: "square.and.arrow.down"
                )
            }

            if let galleryURL = gallery.galleryURL {
                ShareLink(item: galleryURL) {
                    Label(
                        L10n.Localizable.DetailView.ToolbarItem.Button.share,
                        systemImage: "square.and.arrow.up"
                    )
                }
            }
        }
        .disabled(operationInProgress)
    }

    private func performFavorite(index: Int) {
        guard !operationInProgress else { return }
        operationInProgress = true
        Task { @MainActor in
            let result = await FavorGalleryRequest(
                gid: gallery.id,
                token: gallery.token,
                favIndex: index
            )
            .response()
            switch result {
            case .success:
                if var detail = databaseClient.fetchGalleryDetail(gid: gallery.id) {
                    detail.isFavorited = true
                    databaseClient.cacheGalleryDetail(detail)
                }
                favoriteOverride = true
                hapticsClient.generateNotificationFeedback(.success)
            case .failure:
                hapticsClient.generateNotificationFeedback(.error)
            }
            operationInProgress = false
        }
    }

    private func performUnfavorite() {
        guard !operationInProgress else { return }
        operationInProgress = true
        Task { @MainActor in
            let result = await UnfavorGalleryRequest(gid: gallery.id).response()
            switch result {
            case .success:
                if var detail = databaseClient.fetchGalleryDetail(gid: gallery.id) {
                    detail.isFavorited = false
                    databaseClient.cacheGalleryDetail(detail)
                }
                favoriteOverride = false
                hapticsClient.generateNotificationFeedback(.success)
            case .failure:
                hapticsClient.generateNotificationFeedback(.error)
            }
            operationInProgress = false
        }
    }

    private func performCache() {
        guard !operationInProgress else { return }
        operationInProgress = true
        Task { @MainActor in
            if let item = await cacheClient.item(gallery.id) {
                if !item.isComplete && !item.status.isActive {
                    await cacheClient.resume(gallery.id, .init(setting: setting))
                }
                hapticsClient.generateNotificationFeedback(.success)
                operationInProgress = false
                return
            }

            var detail = databaseClient.fetchGalleryDetail(gid: gallery.id)
            if detail == nil, let galleryURL = gallery.galleryURL {
                let result = await GalleryDetailRequest(
                    gid: gallery.id,
                    galleryURL: galleryURL
                )
                .response()
                if case .success(let response) = result {
                    detail = response.0
                    databaseClient.cacheGalleries([gallery])
                    databaseClient.cacheGalleryDetail(response.0)
                    databaseClient.updateGalleryTags(
                        gid: gallery.id,
                        tags: response.1.tags
                    )
                }
            }

            if let detail {
                await cacheClient.enqueue(gallery, detail, .init(setting: setting))
                hapticsClient.generateNotificationFeedback(.success)
            } else {
                hapticsClient.generateNotificationFeedback(.error)
            }
            operationInProgress = false
        }
    }
}

private struct GalleryDetailContextPreview: View {
    private let gallery: Gallery
    private let configuration: GalleryContextMenuConfiguration
    private let store: StoreOf<DetailReducer>

    init(
        gallery: Gallery,
        configuration: GalleryContextMenuConfiguration
    ) {
        self.gallery = gallery
        self.configuration = configuration
        var state = DetailReducer.State()
        state.gallery = gallery
        store = Store(initialState: state) {
            DetailReducer()
        }
    }

    var body: some View {
        NavigationStack {
            DetailView(
                store: store,
                gid: gallery.id,
                user: configuration.user,
                setting: .constant(configuration.setting),
                blurRadius: configuration.blurRadius,
                tagTranslator: configuration.tagTranslator
            )
            .content
            .navigationTitle(L10n.Localizable.DetailView.ContextMenu.Button.detail)
            .navigationBarTitleDisplayMode(.inline)
        }
        .frame(
            minWidth: 300,
            idealWidth: 420,
            minHeight: 420,
            idealHeight: 620
        )
        .onAppear {
            store.send(.onPreviewAppear(gallery.id))
        }
        .onDisappear {
            store.send(.teardown)
        }
    }
}

struct GalleryListActionMenu: View {
    let actions: [GalleryListAction]

    var body: some View {
        Menu {
            ForEach(actions.indices, id: \.self) { index in
                let item = actions[index]
                Button(role: item.role.buttonRole, action: item.action) {
                    Label(item.title, systemImage: item.systemImage)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 30, height: 30)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.Localizable.CacheView.Button.more)
    }
}

struct GalleryListStatusView: View {
    let status: GalleryListStatus
    let actions: [GalleryListAction]
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 5) {
            HStack(spacing: 6) {
                Label(status.text, systemImage: status.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.tone.color)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if !actions.isEmpty {
                    GalleryListActionMenu(actions: actions)
                }
            }

            if let message = status.message, !message.isEmpty {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 1 : 2)
            }

            if let progress = status.progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            }

            if let detailText = status.detailText, !detailText.isEmpty {
                Text(detailText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct GalleryDetailCell: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    private let gallery: Gallery
    private let setting: Setting
    private let presentation: GalleryListPresentation?
    private let actions: [GalleryListAction]
    private let translateAction: ((String) -> (String, TagTranslation?))?

    init(
        gallery: Gallery,
        setting: Setting,
        presentation: GalleryListPresentation? = nil,
        actions: [GalleryListAction] = [],
        translateAction: ((String) -> (String, TagTranslation?))? = nil
    ) {
        self.gallery = gallery
        self.setting = setting
        self.presentation = presentation
        self.actions = actions
        self.translateAction = translateAction
    }

    private var tagColor: Color {
        colorScheme == .light ? Color(.systemGray5) : Color(.systemGray4)
    }
    private var coverPixelSize: CGSize {
        .init(
            width: Defaults.ImageSize.rowW * displayScale,
            height: Defaults.ImageSize.rowH * displayScale
        )
    }
    private var coverURL: URL? {
        presentation?.coverURL ?? gallery.coverURL
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        HStack(alignment: .top, spacing: 12) {
            KFImage(coverURL)
                .placeholder { Placeholder(style: .activity(ratio: Defaults.ImageSize.rowAspect)) }
                .downsampling(size: coverPixelSize)
                .backgroundDecode()
                .loadDiskFileSynchronously(false)
                .cancelOnDisappear(true)
                .cacheMemoryOnly(coverURL?.isFileURL == true)
                .fade(duration: 0.15)
                .resizable()
                .scaledToFill()
                .frame(
                    width: Defaults.ImageSize.rowW,
                    height: Defaults.ImageSize.rowH
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 7) {
                Text(gallery.title)
                    .lineLimit(3)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if let uploader = gallery.uploader, !uploader.isEmpty {
                    Label(uploader, systemImage: "person")
                        .lineLimit(1)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                let tagContents = gallery.tagContents(maximum: setting.listTagsNumberMaximum)
                if setting.showsTagsInList, !tagContents.isEmpty {
                    TagCloudView(data: tagContents) { content in
                        let translation = translateAction?(content.rawNamespace + content.text).1
                        TagCloudCell(
                            text: translation?.displayValue ?? content.text,
                            imageURL: translation?.valueImageURL,
                            showsImages: setting.showsImagesInTags,
                            font: .caption2, padding: .init(top: 2, leading: 4, bottom: 2, trailing: 4),
                            textColor: content.backgroundColor != nil ? content.textColor ?? .secondary : .secondary,
                            backgroundColor: content.backgroundColor ?? tagColor
                        )
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    RatingView(rating: gallery.rating)
                        .font(.caption)
                        .foregroundStyle(.yellow)

                    Spacer(minLength: 4)

                    HStack(spacing: 10) {
                        if let language = gallery.language {
                            Text(language.value)
                        }
                        HStack(spacing: 2) {
                            Image(systemSymbol: .photoOnRectangleAngled)
                            Text(String(gallery.pageCount))
                        }
                    }
                    .lineLimit(1)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.75)
                }

                HStack(alignment: .center) {
                    CategoryLabel(text: gallery.category.value, color: gallery.color)
                    Spacer(minLength: 4)
                    Text(gallery.formattedDateString)
                        .lineLimit(1)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(0.75)
                }

                if let status = presentation?.status {
                    Divider()
                    GalleryListStatusView(
                        status: status,
                        actions: actions,
                        compact: false
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .contentShape(shape)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: shape)
        .overlay {
            shape.stroke(
                .primary.opacity(colorScheme == .light ? 0.06 : 0.12),
                lineWidth: 0.5
            )
        }
        .hoverEffect(.highlight)
    }
}

struct GalleryDetailCell_Previews: PreviewProvider {
    static var previews: some View {
        GalleryDetailCell(gallery: .preview, setting: Setting())
    }
}
