//
//  CacheView.swift
//  EhPanda
//

import SwiftUI
import Kingfisher
import ComposableArchitecture

struct CacheView: View {
    @Bindable private var store: StoreOf<CacheReducer>
    private let user: User
    @Binding private var setting: Setting
    private let blurRadius: Double
    private let tagTranslator: TagTranslator
    @State private var showsDeleteAllConfirmation = false

    init(
        store: StoreOf<CacheReducer>,
        user: User,
        setting: Binding<Setting>,
        blurRadius: Double,
        tagTranslator: TagTranslator
    ) {
        self.store = store
        self.user = user
        _setting = setting
        self.blurRadius = blurRadius
        self.tagTranslator = tagTranslator
    }

    private var options: CacheDownloadOptions {
        .init(setting: setting)
    }

    private var filteredItems: [GalleryCacheItem] {
        guard !store.searchText.isEmpty else { return store.items }
        return store.items.filter {
            $0.detail.title.localizedCaseInsensitiveContains(store.searchText)
                || $0.detail.jpnTitle?.localizedCaseInsensitiveContains(store.searchText) == true
                || $0.gallery.title.localizedCaseInsensitiveContains(store.searchText)
                || $0.gallery.uploader?.localizedCaseInsensitiveContains(store.searchText) == true
                || $0.id.localizedCaseInsensitiveContains(store.searchText)
        }
    }

    private var activeItems: [GalleryCacheItem] {
        filteredItems.filter { !$0.isComplete }
    }

    private var completedItems: [GalleryCacheItem] {
        filteredItems.filter(\.isComplete)
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.items.isEmpty {
                    ContentUnavailableView(
                        L10n.Localizable.CacheView.Empty.Title.cache,
                        systemImage: "square.and.arrow.down",
                        description: Text(L10n.Localizable.CacheView.Empty.Description.cache)
                    )
                } else {
                    cacheList
                }
            }
            .navigationTitle(L10n.Localizable.CacheView.Title.cache)
            .navigationDestination(item: $store.route.sending(\.setNavigation).detail) { gid in
                DetailView(
                    store: store.scope(state: \.detailState.wrappedValue!, action: \.detail),
                    gid: gid,
                    user: user,
                    setting: $setting,
                    blurRadius: blurRadius,
                    tagTranslator: tagTranslator
                )
            }
            .searchable(
                text: $store.searchText,
                prompt: L10n.Localizable.CacheView.Search.Prompt.cache
            )
            .toolbar { toolbarContent }
            .confirmationDialog(
                L10n.Localizable.CacheView.Confirmation.DeleteAll.title,
                isPresented: $showsDeleteAllConfirmation,
                titleVisibility: .visible
            ) {
                Button(
                    L10n.Localizable.CacheView.Button.deleteAll,
                    role: .destructive
                ) {
                    store.send(.deleteAll)
                }
            } message: {
                Text(L10n.Localizable.CacheView.Confirmation.DeleteAll.message)
            }
        }
        .onAppear {
            store.send(.onAppear(
                options,
                resumesAutomatically: setting.cacheResumesAutomatically
            ))
        }
    }

    private var cacheList: some View {
        List {
            if !activeItems.isEmpty {
                Section(L10n.Localizable.CacheView.Section.Title.inProgress) {
                    ForEach(activeItems) { item in
                        cacheRow(item)
                    }
                }
            }
            if !completedItems.isEmpty {
                Section(L10n.Localizable.CacheView.Section.Title.completed) {
                    ForEach(completedItems) { item in
                        cacheRow(item)
                    }
                }
            }
            if filteredItems.isEmpty {
                ContentUnavailableView.search(text: store.searchText)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func cacheRow(_ item: GalleryCacheItem) -> some View {
        CacheRow(
            item: item,
            title: displayTitle(for: item)
        ) { action in
            switch action {
            case .open:
                store.send(.openDetail(item.id))
            case .pause:
                store.send(.pause(item.id))
            case .resume:
                store.send(.resume(item.id, options))
            case .delete:
                store.send(.delete(item.id))
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                store.send(.delete(item.id))
            } label: {
                Label(L10n.Localizable.CacheView.Button.delete, systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if item.status.isActive {
                Button {
                    store.send(.pause(item.id))
                } label: {
                    Label(L10n.Localizable.CacheView.Button.pause, systemImage: "pause.fill")
                }
                .tint(.orange)
            } else if !item.isComplete {
                Button {
                    store.send(.resume(item.id, options))
                } label: {
                    Label(
                        item.status == .failed
                            ? L10n.Localizable.CacheView.Button.retry
                            : L10n.Localizable.CacheView.Button.resume,
                        systemImage: item.status == .failed
                            ? "arrow.clockwise"
                            : "play.fill"
                    )
                }
                .tint(.green)
            }
        }
    }

    private func displayTitle(for item: GalleryCacheItem) -> String {
        if setting.displaysJapaneseTitle,
           let title = item.detail.jpnTitle,
           !title.isEmpty
        {
            return title
        }
        return item.detail.title.isEmpty ? item.gallery.title : item.detail.title
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    store.send(.resumeAll(options))
                } label: {
                    Label(L10n.Localizable.CacheView.Button.resumeAll, systemImage: "play.fill")
                }
                .disabled(!store.items.contains(where: { !$0.isComplete && !$0.status.isActive }))

                Button {
                    store.send(.pauseAll)
                } label: {
                    Label(L10n.Localizable.CacheView.Button.pauseAll, systemImage: "pause.fill")
                }
                .disabled(!store.items.contains(where: \.status.isActive))

                Divider()

                Button(role: .destructive) {
                    showsDeleteAllConfirmation = true
                } label: {
                    Label(L10n.Localizable.CacheView.Button.deleteAll, systemImage: "trash")
                }
                .disabled(store.items.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel(L10n.Localizable.CacheView.Button.more)
        }
    }
}

private enum CacheRowAction {
    case open
    case pause
    case resume
    case delete
}

private struct CacheRow: View {
    let item: GalleryCacheItem
    let title: String
    let action: (CacheRowAction) -> Void

    private var statusText: String {
        switch item.status {
        case .queued:
            return L10n.Localizable.CacheView.Status.queued
        case .resolving:
            return L10n.Localizable.CacheView.Status.resolving
        case .downloading:
            return L10n.Localizable.CacheView.Status.downloading
        case .paused:
            return L10n.Localizable.CacheView.Status.paused
        case .completed:
            return L10n.Localizable.CacheView.Status.completed
        case .failed:
            return L10n.Localizable.CacheView.Status.failed
        }
    }

    private var detailText: String {
        let pages = L10n.Localizable.CacheView.Value.pages(
            "\(item.cachedPageCount)",
            "\(item.pageCount)"
        )
        guard item.byteCount > 0 else { return pages }
        return [
            pages,
            ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file)
        ]
        .joined(separator: "  ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                action(.open)
            } label: {
                HStack(spacing: 12) {
                    cover
                        .frame(width: 54, height: 76)
                        .clipShape(.rect(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.body.weight(.semibold))
                            .lineLimit(2)

                        HStack(spacing: 5) {
                            Image(systemName: statusSymbol)
                            Text(statusText)
                        }
                        .font(.caption)
                        .foregroundStyle(statusColor)

                        if item.status == .failed,
                           let errorDescription = item.errorDescription,
                           !errorDescription.isEmpty
                        {
                            Text(errorDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        if !item.isComplete {
                            ProgressView(value: item.progress)
                                .progressViewStyle(.linear)
                        }

                        Text(detailText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 4)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Menu {
                if item.status.isActive {
                    Button {
                        action(.pause)
                    } label: {
                        Label(L10n.Localizable.CacheView.Button.pause, systemImage: "pause.fill")
                    }
                } else if !item.isComplete {
                    Button {
                        action(.resume)
                    } label: {
                        Label(
                            item.status == .failed
                                ? L10n.Localizable.CacheView.Button.retry
                                : L10n.Localizable.CacheView.Button.resume,
                            systemImage: item.status == .failed
                                ? "arrow.clockwise"
                                : "play.fill"
                        )
                    }
                }
                Button(role: .destructive) {
                    action(.delete)
                } label: {
                    Label(L10n.Localizable.CacheView.Button.delete, systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 32, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private var cover: some View {
        let url = item.coverFileURL ?? item.detail.coverURL ?? item.gallery.coverURL
        return KFImage(url)
            .placeholder { Color(.secondarySystemFill) }
            .cacheMemoryOnly(url?.isFileURL == true)
            .defaultModifier(withRoundedCorners: false)
            .scaledToFill()
    }

    private var statusSymbol: String {
        switch item.status {
        case .queued:
            return "clock"
        case .resolving:
            return "link"
        case .downloading:
            return "arrow.down.circle.fill"
        case .paused:
            return "pause.circle.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .completed:
            return .green
        case .failed:
            return .red
        case .paused:
            return .orange
        case .queued, .resolving, .downloading:
            return .accentColor
        }
    }
}

struct CacheView_Previews: PreviewProvider {
    static var previews: some View {
        CacheView(
            store: .init(initialState: .init(), reducer: CacheReducer.init),
            user: .init(),
            setting: .constant(.init()),
            blurRadius: 0,
            tagTranslator: .init()
        )
    }
}
