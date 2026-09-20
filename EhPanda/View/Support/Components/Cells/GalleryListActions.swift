//
//  GalleryListActions.swift
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
    @State private var shareURL: URL?

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
                            isFavorited: isFavorited ?? configuration.defaultFavoriteState,
                            shareAction: { shareURL = $0 }
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
                .sheet(item: $shareURL, id: \.absoluteString) { url in
                    ActivityView(activityItems: [url])
                }
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
    let shareAction: (URL) -> Void

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
                Button {
                    shareAction(galleryURL)
                } label: {
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
