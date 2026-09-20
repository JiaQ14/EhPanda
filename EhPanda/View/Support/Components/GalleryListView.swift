//
//  GalleryListView.swift
//  EhPanda
//

import UIKit
import SwiftUI
import Kingfisher

struct GalleryListView: UIViewControllerRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.inSheet) private var inSheet
    @Environment(\.isStandaloneGalleryWindow) private var standalone
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.locale) private var locale
    @Environment(\.galleryContextMenuConfiguration) var contextMenu

    let galleries: [Gallery]
    let setting: Setting
    let translationRevision: TagTranslator.RenderRevision?
    let datasetIdentity: AnyHashable
    let presentations: [String: GalleryListPresentation]
    let actionsProvider: ((String) -> [GalleryListAction])?
    let pageNumber: PageNumber?
    let loadingState: LoadingState
    let footerLoadingState: LoadingState
    let fetchAction: (() async -> Void)?
    let fetchMoreAction: (() -> Void)?
    let navigateAction: ((String) -> Void)?
    let translateAction: ((String) -> (String, TagTranslation?))?

    var environment: GalleryListEnvironment {
        .init(colorScheme: colorScheme, dynamicTypeSize: dynamicTypeSize, inSheet: inSheet,
              standalone: standalone, layoutDirection: layoutDirection, locale: locale)
    }

    func makeUIViewController(context: Context) -> GalleryListController {
        GalleryListController(input: self)
    }

    func updateUIViewController(_ controller: GalleryListController, context: Context) {
        controller.update(self)
    }

    static func dismantleUIViewController(_ controller: GalleryListController, coordinator: ()) {
        controller.tearDown()
    }
}

struct GalleryListEnvironment: Equatable {
    let colorScheme: ColorScheme
    let dynamicTypeSize: DynamicTypeSize
    let inSheet: Bool
    let standalone: Bool
    let layoutDirection: LayoutDirection
    let locale: Locale
}

private struct GalleryListAppearance: Equatable {
    let mode: ListDisplayMode
    let tags: Bool
    let tagCount: Int
    let tagImages: Bool
    let translated: Bool

    init(_ setting: Setting) {
        mode = setting.listDisplayMode
        tags = setting.showsTagsInList
        tagCount = setting.listTagsNumberMaximum
        tagImages = setting.showsImagesInTags
        translated = setting.translatesTags
    }
}

struct GalleryListRenderKey: Equatable {
    let title: String
    let rating: Float
    let tags: [GalleryTag]
    let category: Category
    let uploader: String?
    let pages: Int
    let posted: Date
    let cover: URL?
    let galleryURL: URL?
    let token: String
    let presentation: GalleryListPresentation?

    init(_ gallery: Gallery, presentation: GalleryListPresentation?) {
        title = gallery.title
        rating = gallery.rating
        tags = gallery.tags
        category = gallery.category
        uploader = gallery.uploader
        pages = gallery.pageCount
        posted = gallery.postedDate
        cover = gallery.coverURL
        galleryURL = gallery.galleryURL
        token = gallery.token
        self.presentation = presentation
    }
}

private struct GalleryListRow {
    let gallery: Gallery
    let key: GalleryListRenderKey
    let layout: GalleryCardLayout
}

struct GalleryListAnchor {
    let id: String
    let distance: CGFloat
    let fraction: CGFloat
    let extent: CGFloat
}

struct GalleryPaginationKey: Equatable {
    let page: PageNumber?
    let first: String?
    let last: String?
    let count: Int
}

final class GalleryListController: UIViewController {
    private(set) var input: GalleryListView
    private(set) var scrollView: UIScrollView!
    private var table: UITableView?
    private var collection: UICollectionView?
    private let masonry = GalleryMasonryLayout()
    private var rows = [GalleryListRow]()
    private var width: CGFloat = 0
    private var appearance: GalleryListAppearance?
    private var environment: GalleryListEnvironment?
    private var translationRevision: TagTranslator.RenderRevision?
    private var dataset: AnyHashable?
    private var hasFooter = false
    private var footerState: LoadingState = .idle
    private var isApplying = false
    private var pendingInput: GalleryListView?
    private var refreshTask: Task<Void, Never>?
    private var refreshFinished = false
    private var paginationKey: GalleryPaginationKey?
    private var prefetchers = [String: ImagePrefetcher]()
    private var isActive = true

    init(input: GalleryListView) {
        self.input = input
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        installScrollView()
    }

    private func installScrollView() {
        let previous = scrollView
        previous?.removeFromSuperview()
        table = nil
        collection = nil
        if input.setting.listDisplayMode == .detail {
            let table = UITableView(frame: .zero, style: .plain)
            table.dataSource = self
            table.delegate = self
            table.prefetchDataSource = self
            table.separatorStyle = .none
            table.estimatedRowHeight = 0
            table.estimatedSectionHeaderHeight = 0
            table.estimatedSectionFooterHeight = 0
            table.sectionHeaderTopPadding = 0
            table.register(UITableViewCell.self, forCellReuseIdentifier: "gallery")
            self.table = table
            scrollView = table
        } else {
            let collection = UICollectionView(frame: .zero, collectionViewLayout: masonry)
            collection.dataSource = self
            collection.delegate = self
            collection.prefetchDataSource = self
            collection.selfSizingInvalidation = .disabled
            collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "gallery")
            self.collection = collection
            scrollView = collection
        }
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.automaticallyAdjustsScrollIndicatorInsets = false
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true
        scrollView.backgroundColor = .systemGroupedBackground
        scrollView.accessibilityIdentifier = "gallery-list"
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        setContentScrollView(scrollView, for: .all)
        updateRefreshControl()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Height changes (keyboard, bars, sheet detents) do not invalidate card layout.
        if abs(view.bounds.width - width) > 0.5 {
            commit(input)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        fetchMoreIfNeeded()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopPrefetching()
    }

    func update(_ input: GalleryListView) {
        guard isViewLoaded else { self.input = input; return }
        if isApplying || scrollView.isDragging || scrollView.isDecelerating {
            pendingInput = input
            return
        }
        commit(input)
    }

    private func commit(_ next: GalleryListView) {
        guard !isApplying, view.bounds.width > 0 else { input = next; return }
        isApplying = true
        defer {
            isApplying = false
            drainPendingInput()
            Task { @MainActor [weak self] in self?.fetchMoreIfNeeded() }
        }
        let oldIDs = rows.map { $0.gallery.id }
        let anchor = captureAnchor()
        let mayRestoreOffset = scrollView.contentOffset.y >= 0 && scrollView.refreshControl?.isRefreshing != true
        let oldEnvironment = environment
        let menuChanged = input.contextMenu?.user != next.contextMenu?.user
            || input.setting.accentColor != next.setting.accentColor
        let nextAppearance = GalleryListAppearance(next.setting)
        let modeChanged = appearance?.mode != nil && appearance?.mode != nextAppearance.mode
        let geometryChanged = width != view.bounds.width || appearance != nextAppearance
            || environment?.dynamicTypeSize != next.environment.dynamicTypeSize
            || environment?.locale != next.environment.locale
            || environment?.layoutDirection != next.environment.layoutDirection
            || translationRevision != next.translationRevision
        let datasetChanged = dataset != nil && dataset != next.datasetIdentity
        let previousRows = Dictionary(uniqueKeysWithValues: rows.map { ($0.gallery.id, $0) })
        input = next
        width = view.bounds.width
        appearance = nextAppearance
        environment = next.environment
        translationRevision = next.translationRevision
        dataset = next.datasetIdentity
        let cardWidth = GalleryListGeometry.cardWidth(
            viewport: width, mode: next.setting.listDisplayMode,
            accessibility: next.environment.dynamicTypeSize.isAccessibilitySize
        )
        var seen = Set<String>()
        var changed = Set<String>()
        rows = next.galleries.compactMap { gallery in
            guard seen.insert(gallery.id).inserted else { return nil }
            let key = GalleryListRenderKey(gallery, presentation: next.presentations[gallery.id])
            if !geometryChanged, let old = previousRows[gallery.id], old.key == key { return old }
            changed.insert(gallery.id)
            return GalleryListRow(
                gallery: gallery, key: key,
                layout: GalleryCardLayout(
                    gallery: gallery, setting: next.setting, presentation: next.presentations[gallery.id],
                    width: cardWidth, contentSize: next.environment.dynamicTypeSize.galleryContentSizeCategory,
                    rightToLeft: next.environment.layoutDirection == .rightToLeft,
                    translate: next.translateAction
                )
            )
        }
        let newIDs = rows.map { $0.gallery.id }
        let newFooter = next.pageNumber?.hasNextPage() == true
        let footerChanged = hasFooter != newFooter || footerState != next.footerLoadingState
        let oldFooterHeight = footerHeight
        let structureChanged = oldIDs != newIDs || hasFooter != newFooter
        hasFooter = newFooter
        footerState = next.footerLoadingState
        if modeChanged {
            refreshTask?.cancel()
            refreshTask = nil
            refreshFinished = false
            stopPrefetching()
            installScrollView()
            view.layoutIfNeeded()
        }
        updateRefreshControl()
        let heightsChanged = rows.contains { previousRows[$0.gallery.id]?.layout.height != $0.layout.height }
        if geometryChanged || structureChanged || heightsChanged || datasetChanged || oldFooterHeight != footerHeight {
            // Commit data, sizes and offset together before the next rendered frame.
            // No async measurement callbacks or queued scroll restores are involved.
            UIView.performWithoutAnimation {
                masonry.setGeometry(GalleryListGeometry.waterfall(
                    viewport: width, heights: rows.map { $0.layout.height },
                    accessibility: next.environment.dynamicTypeSize.isAccessibilitySize,
                    footerHeight: hasFooter ? footerHeight : nil,
                    rightToLeft: next.environment.layoutDirection == .rightToLeft
                ))
                table?.reloadData()
                collection?.reloadData()
                scrollView.layoutIfNeeded()
                // Pull-to-refresh owns negative offsets and its settling animation.
                if mayRestoreOffset, datasetChanged {
                    scrollView.setContentOffset(.zero, animated: false)
                } else if mayRestoreOffset, let anchor,
                          let index = rows.firstIndex(where: { $0.gallery.id == anchor.id }) {
                    let frame = rowFrame(index)
                    let resized = geometryChanged || abs(anchor.extent - frame.height) > 0.5
                    let distance = resized && anchor.distance < 0
                        ? anchor.fraction * frame.height : anchor.distance
                    let y = frame.minY - distance
                    let maximum = max(0, scrollView.contentSize.height - scrollView.bounds.height)
                    scrollView.setContentOffset(CGPoint(x: 0, y: min(max(0, y), maximum)), animated: false)
                } else if mayRestoreOffset, !oldIDs.isEmpty && oldIDs != newIDs {
                    scrollView.setContentOffset(.zero, animated: false)
                }
            }
            let valid = Set(newIDs)
            for id in Array(prefetchers.keys) where !valid.contains(id) {
                prefetchers.removeValue(forKey: id)?.stop()
            }
            if datasetChanged || newIDs != oldIDs { paginationKey = nil }
        } else if oldEnvironment != environment || !changed.isEmpty || footerChanged || menuChanged {
            reconfigureVisibleCells()
        }
    }

    private var footerHeight: CGFloat { footerState == .idle ? 1 : 56 }
    private var itemCount: Int { rows.count + (hasFooter ? 1 : 0) }

    private func rowFrame(_ index: Int) -> CGRect {
        if let table { return table.rectForRow(at: IndexPath(row: index, section: 0)) }
        return masonry.geometry.frames.indices.contains(index) ? masonry.geometry.frames[index] : .zero
    }

    func captureAnchor() -> GalleryListAnchor? {
        guard scrollView != nil else { return nil }
        let visible = table?.indexPathsForVisibleRows ?? collection?.indexPathsForVisibleItems ?? []
        let top = scrollView.contentOffset.y
        let first = visible.filter { $0.item < rows.count && rowFrame($0.item).maxY > top }
            .min { rowFrame($0.item).minY < rowFrame($1.item).minY }
        guard let first else { return nil }
        let frame = rowFrame(first.item)
        let distance = frame.minY - top
        return .init(id: rows[first.item].gallery.id, distance: distance,
                     fraction: distance / max(1, frame.height), extent: frame.height)
    }

    private func configuration(at index: Int) -> UIHostingConfiguration<AnyView, EmptyView> {
        if index >= rows.count {
            let state = footerState
            return UIHostingConfiguration {
                AnyView(Group {
                    if state == .idle {
                        Color.clear.frame(height: 1).accessibilityHidden(true)
                    } else {
                        FetchMoreFooter(loadingState: state, retryAction: { [weak self] in
                            self?.input.fetchMoreAction?()
                        }).frame(height: 56)
                    }
                })
            }.margins(.all, 0)
        }
        let row = rows[index]
        let environment = input.environment
        let actions = input.actionsProvider?(row.gallery.id) ?? []
        let detail = input.setting.listDisplayMode == .detail
        return UIHostingConfiguration {
            AnyView(
                GalleryListCard(
                    gallery: row.gallery, presentation: row.key.presentation,
                    actions: actions, layout: row.layout
                )
                .galleryContextMenu(gallery: row.gallery, actions: actions)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { [weak self] in self?.input.navigateAction?(row.gallery.id) }
                .accessibilityActions {
                    ForEach(actions.indices, id: \.self) { index in
                        Button(actions[index].title, action: actions[index].action)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, detail ? 6 : 0)
                .environment(\.colorScheme, environment.colorScheme)
                .environment(\.dynamicTypeSize, environment.dynamicTypeSize)
                .environment(\.inSheet, environment.inSheet)
                .environment(\.isStandaloneGalleryWindow, environment.standalone)
                .environment(\.layoutDirection, environment.layoutDirection)
                .environment(\.locale, environment.locale)
                .environment(\.galleryContextMenuConfiguration, input.contextMenu)
                .tint(input.setting.accentColor)
                .accentColor(input.setting.accentColor)
            )
        }.margins(.all, 0)
    }

    private func reconfigureVisibleCells() {
        for index in table?.indexPathsForVisibleRows ?? [] {
            table?.cellForRow(at: index)?.contentConfiguration = configuration(at: index.row)
        }
        for index in collection?.indexPathsForVisibleItems ?? [] {
            collection?.cellForItem(at: index)?.contentConfiguration = configuration(at: index.item)
        }
    }

    private func updateRefreshControl() {
        guard input.fetchAction != nil else {
            scrollView.refreshControl = nil
            return
        }
        if scrollView.refreshControl == nil {
            let refresh = UIRefreshControl()
            refresh.addTarget(self, action: #selector(Self.refresh), for: .valueChanged)
            scrollView.refreshControl = refresh
        }
    }

    @objc private func refresh() {
        guard refreshTask == nil, let action = input.fetchAction else { return }
        refreshFinished = false
        paginationKey = nil
        refreshTask = Task { [weak self] in
            await action()
            guard !Task.isCancelled else { return }
            await Task.yield()
            self?.refreshFinished = true
            self?.finishRefreshIfPossible()
        }
    }

    private func finishRefreshIfPossible() {
        guard refreshFinished, !scrollView.isDragging, !scrollView.isDecelerating else { return }
        scrollView.refreshControl?.endRefreshing()
        refreshTask = nil
        refreshFinished = false
    }

    private func drainPendingInput() {
        guard !isApplying, !scrollView.isDragging, !scrollView.isDecelerating,
              let pending = pendingInput else { return }
        pendingInput = nil
        commit(pending)
    }

    private func fetchMoreIfNeeded() {
        guard isActive, view.window != nil, !isApplying, hasFooter,
              input.loadingState == .idle, footerState == .idle,
              refreshTask == nil, let action = input.fetchMoreAction, !rows.isEmpty,
              scrollView.contentOffset.y + scrollView.bounds.height + 300 >= scrollView.contentSize.height
        else { return }
        let key = GalleryPaginationKey(page: input.pageNumber, first: rows.first?.gallery.id,
                                       last: rows.last?.gallery.id, count: rows.count)
        guard key != paginationKey else { return }
        paginationKey = key
        action()
    }

    private func select(_ index: Int) {
        guard rows.indices.contains(index) else { return }
        input.navigateAction?(rows[index].gallery.id)
    }

    private func swipeActions(_ index: Int, edge: GalleryListAction.Edge) -> UISwipeActionsConfiguration? {
        guard rows.indices.contains(index) else { return nil }
        let actions = input.actionsProvider?(rows[index].gallery.id).filter { $0.edge == edge } ?? []
        guard !actions.isEmpty else { return nil }
        let configuration = UISwipeActionsConfiguration(actions: actions.map { action in
            let item = UIContextualAction(
                style: action.role == .destructive ? .destructive : .normal, title: action.title
            ) { _, _, completion in
                action.action()
                completion(true)
            }
            item.image = UIImage(systemName: action.systemImage)
            item.backgroundColor = UIColor(action.tint.color)
            return item
        })
        configuration.performsFirstActionWithFullSwipe = edge == .leading
        return configuration
    }

    private func prefetch(_ indices: [IndexPath]) {
        for index in indices where rows.indices.contains(index.item) {
            let row = rows[index.item]
            guard prefetchers[row.gallery.id] == nil,
                  let url = row.key.presentation?.coverURL ?? row.gallery.coverURL else { continue }
            let scale = view.traitCollection.displayScale
            let processor = DownsamplingImageProcessor(size: CGSize(
                width: row.layout.cover.width * scale, height: row.layout.cover.height * scale
            ))
            var options: KingfisherOptionsInfo = [.processor(processor), .backgroundDecode]
            if url.isFileURL { options.append(.cacheMemoryOnly) }
            let prefetcher = ImagePrefetcher(urls: [url], options: options)
            prefetchers[row.gallery.id] = prefetcher
            prefetcher.start()
        }
    }

    private func cancelPrefetch(_ indices: [IndexPath]) {
        for index in indices where rows.indices.contains(index.item) {
            prefetchers.removeValue(forKey: rows[index.item].gallery.id)?.stop()
        }
    }

    private func stopPrefetching() {
        prefetchers.values.forEach { $0.stop() }
        prefetchers.removeAll()
    }

    func tearDown() {
        isActive = false
        refreshTask?.cancel()
        refreshTask = nil
        pendingInput = nil
        stopPrefetching()
        scrollView?.refreshControl?.endRefreshing()
        table?.delegate = nil
        table?.dataSource = nil
        table?.prefetchDataSource = nil
        collection?.delegate = nil
        collection?.dataSource = nil
        collection?.prefetchDataSource = nil
    }
}

extension GalleryListController: UITableViewDataSource, UITableViewDelegate, UITableViewDataSourcePrefetching {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { itemCount }
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        indexPath.row < rows.count ? rows[indexPath.row].layout.height + 12 : footerHeight
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "gallery", for: indexPath)
        cell.backgroundConfiguration = .clear()
        cell.selectionStyle = .none
        cell.contentConfiguration = configuration(at: indexPath.row)
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        select(indexPath.row)
    }
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        cancelPrefetch([indexPath])
        fetchMoreIfNeeded()
    }
    func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
        -> UISwipeActionsConfiguration? { swipeActions(indexPath.row, edge: .leading) }
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
        -> UISwipeActionsConfiguration? { swipeActions(indexPath.row, edge: .trailing) }
    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) { prefetch(indexPaths) }
    func tableView(_ tableView: UITableView, cancelPrefetchingForRowsAt indexPaths: [IndexPath]) {
        cancelPrefetch(indexPaths)
    }
}

extension GalleryListController: UICollectionViewDataSource, UICollectionViewDelegate,
    UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { itemCount }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath)
        -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "gallery", for: indexPath)
        cell.backgroundConfiguration = .clear()
        cell.contentConfiguration = configuration(at: indexPath.item)
        return cell
    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        select(indexPath.item)
    }
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell,
                        forItemAt indexPath: IndexPath) {
        cancelPrefetch([indexPath])
        fetchMoreIfNeeded()
    }
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        prefetch(indexPaths)
    }
    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        cancelPrefetch(indexPaths)
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) { fetchMoreIfNeeded() }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { drainPendingInput(); finishRefreshIfPossible() }
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        drainPendingInput()
        finishRefreshIfPossible()
    }
}

struct GalleryListGeometry: Equatable {
    let frames: [CGRect]
    let contentHeight: CGFloat

    static func columns(viewport: CGFloat, accessibility: Bool) -> Int {
        accessibility ? max(1, Int(viewport / 400)) : max(2, Int(viewport / 220))
    }

    static func cardWidth(viewport: CGFloat, mode: ListDisplayMode, accessibility: Bool) -> CGFloat {
        guard mode == .waterfall else { return max(1, min(1000, viewport - 32)) }
        let columns = columns(viewport: viewport, accessibility: accessibility)
        return max(1, (viewport - 32 - CGFloat(columns - 1) * 12) / CGFloat(columns))
    }

    static func waterfall(viewport: CGFloat, heights: [CGFloat], accessibility: Bool = false,
                          footerHeight: CGFloat? = nil, rightToLeft: Bool = false) -> Self {
        guard viewport > 32 else { return .init(frames: [], contentHeight: 0) }
        let count = columns(viewport: viewport, accessibility: accessibility)
        let width = cardWidth(viewport: viewport, mode: .waterfall, accessibility: accessibility)
        var bottoms = Array(repeating: CGFloat(12), count: count)
        var frames = [CGRect]()
        for height in heights {
            let column = bottoms.indices.min(by: { bottoms[$0] < bottoms[$1] }) ?? 0
            let visualColumn = rightToLeft ? count - 1 - column : column
            let frame = CGRect(x: 16 + CGFloat(visualColumn) * (width + 12), y: bottoms[column],
                               width: width, height: max(1, height.isFinite ? height : 1))
            frames.append(frame)
            bottoms[column] = frame.maxY + 12
        }
        var bottom = heights.isEmpty ? 0 : (bottoms.max() ?? 12)
        if let footerHeight {
            let frame = CGRect(x: 16, y: bottom, width: max(1, viewport - 32), height: max(1, footerHeight))
            frames.append(frame)
            bottom = frame.maxY + 12
        }
        return .init(frames: frames, contentHeight: bottom)
    }
}

final class GalleryMasonryLayout: UICollectionViewLayout {
    private(set) var geometry = GalleryListGeometry(frames: [], contentHeight: 0)
    private var attributes = [UICollectionViewLayoutAttributes]()
    private var buckets = [Int: [Int]]()

    func setGeometry(_ geometry: GalleryListGeometry) {
        guard self.geometry != geometry else { return }
        self.geometry = geometry
        attributes = geometry.frames.enumerated().map { index, frame in
            let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: index, section: 0))
            attributes.frame = frame
            return attributes
        }
        buckets.removeAll(keepingCapacity: true)
        for (index, frame) in geometry.frames.enumerated() {
            for bucket in Int(frame.minY / 512)...Int(frame.maxY / 512) {
                buckets[bucket, default: []].append(index)
            }
        }
        invalidateLayout()
    }

    override var collectionViewContentSize: CGSize {
        CGSize(width: collectionView?.bounds.width ?? 0, height: geometry.contentHeight)
    }
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        attributes.indices.contains(indexPath.item) ? attributes[indexPath.item] : nil
    }
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard !rect.isInfinite, !rect.isNull else { return attributes }
        var indices = Set<Int>()
        for bucket in Int(max(0, rect.minY) / 512)...Int(max(0, rect.maxY) / 512) {
            indices.formUnion(buckets[bucket] ?? [])
        }
        return indices.sorted().compactMap { attributes[$0].frame.intersects(rect) ? attributes[$0] : nil }
    }
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool { false }
    override func shouldInvalidateLayout(
        forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes,
        withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes
    ) -> Bool { false }
}
