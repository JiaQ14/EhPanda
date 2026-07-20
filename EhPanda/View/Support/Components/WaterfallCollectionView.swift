//
//  WaterfallCollectionView.swift
//  EhPanda
//

import UIKit
import SwiftUI
import Kingfisher

struct WaterfallCollectionView: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.inSheet) private var inSheet
    @Environment(\.isStandaloneGalleryWindow)
    private var isStandaloneGalleryWindow
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.locale) private var locale
    @Environment(\.galleryContextMenuConfiguration)
    private var galleryContextMenuConfiguration

    let galleries: [Gallery]
    let setting: Setting
    let translationRevision: TagTranslator.RenderRevision?
    let datasetIdentity: AnyHashable
    let presentations: [String: GalleryListPresentation]
    let actionsProvider: ((String) -> [GalleryListAction])?
    let pageNumber: PageNumber?
    let loadingState: LoadingState
    let footerLoadingState: LoadingState
    let refreshRevision: Int
    let fetchAction: (() async -> Void)?
    let fetchMoreAction: (() -> Void)?
    let navigateAction: ((String) -> Void)?
    let translateAction: ((String) -> (String, TagTranslation?))?

    private var hostEnvironment: WaterfallHostEnvironment {
        .init(
            colorScheme: colorScheme,
            dynamicTypeSize: dynamicTypeSize,
            inSheet: inSheet,
            isStandaloneGalleryWindow: isStandaloneGalleryWindow,
            layoutDirection: layoutDirection,
            locale: locale
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = WaterfallCollectionLayout()
        let collectionView = WaterfallUICollectionView(
            frame: .zero,
            collectionViewLayout: layout
        )
        collectionView.alwaysBounceVertical = true
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.contentInsetAdjustmentBehavior = .always
        collectionView.keyboardDismissMode = .interactive
        collectionView.showsVerticalScrollIndicator = true

        context.coordinator.configureCollectionView(
            collectionView,
            layout: layout
        )
        return collectionView
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
        context.coordinator.update(parent: self, collectionView: collectionView)
    }

    static func dismantleUIView(_ collectionView: UICollectionView, coordinator: Coordinator) {
        coordinator.tearDown()
        collectionView.delegate = nil
        collectionView.prefetchDataSource = nil
        if let collectionView = collectionView as? WaterfallUICollectionView {
            collectionView.boundsSizeWillChangeAction = nil
            collectionView.boundsSizeDidChangeAction = nil
        }
    }
}

extension WaterfallCollectionView {
    final class Coordinator: NSObject {
        private var parent: WaterfallCollectionView
        private weak var collectionView: UICollectionView?
        private var layout: WaterfallCollectionLayout?
        private var dataSource: UICollectionViewDiffableDataSource<WaterfallSection, WaterfallItemID>!

        private var galleriesByID = [String: Gallery]()
        private var gallerySignatures = [String: GalleryRenderSignature]()
        private var presentationsByID = [String: GalleryListPresentation]()
        private var itemIdentifiers = [WaterfallItemID]()
        private var settingSignature: WaterfallSettingSignature
        private var environment: WaterfallHostEnvironment
        private var translationRevision: TagTranslator.RenderRevision?
        private var datasetIdentity: AnyHashable
        private var loadingState: LoadingState
        private var footerLoadingState: LoadingState
        private var refreshRevision: Int

        private var pendingMeasuredHeights =
            [WaterfallItemID: WaterfallPendingMeasurement]()
        private var measurementGenerations = [WaterfallItemID: Int]()
        private var schedulesHeightUpdate = false
        private var lastPaginationTrigger: PaginationTrigger?
        private var prefetchers = [String: WaterfallPrefetchTask]()
        private var pendingBoundsChangeAnchor: WaterfallScrollAnchor?
        private var scrollOperationGeneration = 0
        private var pendingResetGeneration: Int?
        private var awaitsFullReloadCompletion: Bool
        private var refreshStateMachine = GalleryRefreshStateMachine()
        private var refreshTask: Task<Void, Never>?
        private var deferredContentParent: WaterfallCollectionView?
        private var deferredContentUpdateIsScheduled = false
        private var lifecycleGeneration = 0
        private var refreshHasPendingTerminalContent = false
        private var contentCommitGeneration = 0
        private var pendingContentCommitGeneration: Int?

        init(parent: WaterfallCollectionView) {
            self.parent = parent
            settingSignature = .init(setting: parent.setting)
            environment = parent.hostEnvironment
            translationRevision = parent.translationRevision
            datasetIdentity = parent.datasetIdentity
            loadingState = parent.loadingState
            footerLoadingState = parent.footerLoadingState
            refreshRevision = parent.refreshRevision
            awaitsFullReloadCompletion =
                parent.loadingState == .loading
                && parent.galleries.isEmpty
            super.init()
        }

        func configureCollectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout
        ) {
            guard let layout = collectionViewLayout as? WaterfallCollectionLayout else {
                assertionFailure("Unexpected waterfall collection view layout")
                return
            }
            self.collectionView = collectionView
            self.layout = layout

            let registration = UICollectionView.CellRegistration<
                WaterfallHostingCell,
                WaterfallItemID
            > { [weak self] cell, indexPath, itemIdentifier in
                self?.configure(cell: cell, at: indexPath, itemIdentifier: itemIdentifier)
            }
            dataSource = UICollectionViewDiffableDataSource<WaterfallSection, WaterfallItemID>(
                collectionView: collectionView
            ) { collectionView, indexPath, itemIdentifier in
                collectionView.dequeueConfiguredReusableCell(
                    using: registration,
                    for: indexPath,
                    item: itemIdentifier
                )
            }

            collectionView.delegate = self
            collectionView.prefetchDataSource = self
            if let collectionView = collectionView as? WaterfallUICollectionView {
                collectionView.boundsSizeWillChangeAction = { [weak self, weak collectionView] in
                    guard let self, let collectionView else { return }
                    self.pendingMeasuredHeights.removeAll()
                    self.pendingBoundsChangeAnchor = self.captureAnchor(in: collectionView)
                }
                collectionView.boundsSizeDidChangeAction = { [weak self, weak collectionView] in
                    guard let self, let collectionView else { return }
                    let anchor = self.pendingBoundsChangeAnchor
                    self.pendingBoundsChangeAnchor = nil
                    self.restoreAfterLayout(anchor: anchor, in: collectionView)
                }
            }

            let refreshControl = UIRefreshControl()
            refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
            collectionView.refreshControl = refreshControl
        }

        func update(parent: WaterfallCollectionView, collectionView: UICollectionView) {
            if shouldDeferContentUpdate(
                for: parent,
                in: collectionView
            ) {
                deferredContentParent = parent
                return
            }
            deferredContentParent = nil

            let oldSettingSignature = settingSignature
            let oldEnvironment = environment
            let oldTranslationRevision = translationRevision
            let oldDatasetIdentity = datasetIdentity
            let oldLoadingState = loadingState
            let oldFooterLoadingState = footerLoadingState
            let oldRefreshRevision = refreshRevision
            let oldItemIdentifiers = itemIdentifiers
            let oldPresentationsByID = presentationsByID
            let existingSnapshot = dataSource.snapshot()

            self.parent = parent
            settingSignature = .init(setting: parent.setting)
            environment = parent.hostEnvironment
            translationRevision = parent.translationRevision
            datasetIdentity = parent.datasetIdentity
            loadingState = parent.loadingState
            footerLoadingState = parent.footerLoadingState
            refreshRevision = parent.refreshRevision

            let datasetIdentityChanged = oldDatasetIdentity != datasetIdentity
            let beganFullReload =
                oldLoadingState != .loading && loadingState == .loading
                && oldItemIdentifiers.isEmpty
            if beganFullReload {
                awaitsFullReloadCompletion = true
                lastPaginationTrigger = nil
                cancelScheduledScrollRestore()
            }
            let completedFullReload =
                awaitsFullReloadCompletion
                && oldLoadingState == .loading
                && loadingState == .idle
            if datasetIdentityChanged || completedFullReload {
                awaitsFullReloadCompletion = false
            }
            let datasetChanged = datasetIdentityChanged || completedFullReload

            var newGalleriesByID = [String: Gallery]()
            var newGallerySignatures = [String: GalleryRenderSignature]()
            var newPresentationsByID = [String: GalleryListPresentation]()
            var newItemIdentifiers = [WaterfallItemID]()
            var seenIDs = Set<String>()

            for gallery in parent.galleries where seenIDs.insert(gallery.id).inserted {
                newGalleriesByID[gallery.id] = gallery
                newGallerySignatures[gallery.id] = .init(gallery: gallery)
                newPresentationsByID[gallery.id] = parent.presentations[gallery.id]
                newItemIdentifiers.append(.gallery(gallery.id))
            }
            if parent.pageNumber?.hasNextPage() == true {
                newItemIdentifiers.append(.footer)
            }

            let settingChanged = oldSettingSignature != settingSignature
            let sizeEnvironmentChanged =
                oldEnvironment.dynamicTypeSize != environment.dynamicTypeSize
                || oldEnvironment.locale != environment.locale
            let environmentChanged = oldEnvironment != environment
            let translationChanged = oldTranslationRevision != translationRevision
            let changedGalleryIDs = newGallerySignatures.compactMap { id, signature in
                gallerySignatures[id] == signature ? nil : id
            }
            let presentationIDs = Set(oldPresentationsByID.keys)
                .union(newPresentationsByID.keys)
            let changedPresentationIDs = presentationIDs.filter {
                oldPresentationsByID[$0] != newPresentationsByID[$0]
            }
            let presentationLayoutChangedIDs = changedPresentationIDs.filter {
                (oldPresentationsByID[$0]?.status != nil)
                    != (newPresentationsByID[$0]?.status != nil)
            }
            let footerChanged = oldFooterLoadingState != footerLoadingState
            let refreshRevisionChanged = oldRefreshRevision != refreshRevision
            let structureChanged = itemIdentifiers != newItemIdentifiers
            let hasExistingSnapshot = !existingSnapshot.sectionIdentifiers.isEmpty
            let datasetUpdate = WaterfallDatasetUpdateKind.classify(
                oldIdentifiers: oldItemIdentifiers,
                newIdentifiers: newItemIdentifiers,
                hasExistingSnapshot: hasExistingSnapshot,
                datasetChanged: datasetChanged
            )
            let isAppendOnlyChange = datasetUpdate == .append
            let replacesDataset = datasetUpdate == .replace

            let shouldPreserveAnchor =
                !replacesDataset
                && (
                    isAppendOnlyChange
                    || settingChanged
                    || sizeEnvironmentChanged
                    || translationChanged
                    || !changedGalleryIDs.isEmpty
                    || !presentationLayoutChangedIDs.isEmpty
                    || footerChanged
                )
            let anchor = shouldPreserveAnchor ? captureAnchor(in: collectionView) : nil
            galleriesByID = newGalleriesByID
            gallerySignatures = newGallerySignatures
            presentationsByID = newPresentationsByID
            itemIdentifiers = newItemIdentifiers

            let validItemIdentifiers = Set(newItemIdentifiers)
            pendingMeasuredHeights = pendingMeasuredHeights.filter {
                validItemIdentifiers.contains($0.key)
            }
            measurementGenerations = measurementGenerations.filter {
                validItemIdentifiers.contains($0.key)
            }
            for identifier in newItemIdentifiers
            where measurementGenerations[identifier] == nil {
                measurementGenerations[identifier] = 0
            }

            let oldItemSet = Set(existingSnapshot.itemIdentifiers)
            var identifiersToReconfigure = Set<WaterfallItemID>()
            if settingChanged || environmentChanged || translationChanged {
                identifiersToReconfigure.formUnion(
                    newItemIdentifiers.filter {
                        if case .gallery = $0 { return oldItemSet.contains($0) }
                        return false
                    }
                )
            } else {
                identifiersToReconfigure.formUnion(
                    changedGalleryIDs
                        .map(WaterfallItemID.gallery)
                        .filter(oldItemSet.contains)
                )
            }
            identifiersToReconfigure.formUnion(
                changedPresentationIDs
                    .map(WaterfallItemID.gallery)
                    .filter(oldItemSet.contains)
            )
            if footerChanged, oldItemSet.contains(.footer), newItemIdentifiers.contains(.footer) {
                identifiersToReconfigure.insert(.footer)
            }

            var identifiersWithInvalidMeasurements = Set<WaterfallItemID>()
            if settingChanged || sizeEnvironmentChanged || translationChanged {
                identifiersWithInvalidMeasurements.formUnion(
                    newItemIdentifiers.filter {
                        if case .gallery = $0 { return true }
                        return false
                    }
                )
            } else {
                identifiersWithInvalidMeasurements.formUnion(
                    changedGalleryIDs.map(WaterfallItemID.gallery)
                )
                identifiersWithInvalidMeasurements.formUnion(
                    presentationLayoutChangedIDs.map(WaterfallItemID.gallery)
                )
            }
            if footerChanged {
                identifiersWithInvalidMeasurements.insert(.footer)
            }
            invalidatePendingMeasurements(for: identifiersWithInvalidMeasurements)

            let galleryExtraHeight: CGFloat =
                (parent.setting.showsTagsInList ? 210 : 125)
                + (parent.presentations.isEmpty
                    ? 0
                    : GalleryThumbnailCell.statusInformationHeight)
            if replacesDataset {
                layout?.resetColumnAssignments()
            }
            layout?.setItems(
                newItemIdentifiers,
                estimatedGalleryExtraHeight: galleryExtraHeight,
                estimatedGalleryExtraHeightProvider: { [weak self] identifier, itemWidth in
                    guard let self,
                          case .gallery(let id) = identifier,
                          let gallery = self.galleriesByID[id]
                    else { return galleryExtraHeight }
                    return GalleryThumbnailCell.informationHeight(
                        gallery: gallery,
                        setting: self.parent.setting,
                        availableWidth: itemWidth,
                        presentation: self.presentationsByID[id],
                        translateAction: self.parent.translateAction
                    )
                },
                estimatedFooterHeight: parent.footerLoadingState == .idle ? 1 : 50
            )
            layout?.invalidateEstimatedHeights(for: identifiersWithInvalidMeasurements)
            if settingChanged || sizeEnvironmentChanged || translationChanged {
                layout?.removeAllMeasuredHeights()
            } else {
                layout?.removeMeasuredHeights(
                    for: Set(changedGalleryIDs)
                        .union(presentationLayoutChangedIDs)
                        .map(WaterfallItemID.gallery)
                )
            }
            if footerChanged {
                layout?.removeMeasuredHeights(for: [.footer])
            }

            let needsLayoutUpdate = layout?.needsLayoutUpdate == true
            let requiresSnapshotCommit =
                replacesDataset
                || structureChanged
                || !identifiersToReconfigure.isEmpty
            let requiresContentCommit = requiresSnapshotCommit || needsLayoutUpdate
            if refreshStateMachine.phase != .idle {
                if oldLoadingState != .loading, loadingState == .loading {
                    refreshHasPendingTerminalContent = false
                    refreshContentDidCommit(loadingState: loadingState)
                }
                if refreshRevisionChanged {
                    refreshHasPendingTerminalContent = true
                }
            }

            if replacesDataset || parent.pageNumber?.hasNextPage() != true {
                lastPaginationTrigger = nil
            }
            guard requiresContentCommit else {
                reconcileRefreshAfterWorkDrained()
                flushMeasuredHeightsIfPossible()
                fetchMoreIfNeeded(in: collectionView)
                return
            }

            contentCommitGeneration &+= 1
            let commitGeneration = contentCommitGeneration
            pendingContentCommitGeneration = commitGeneration
            let finishContentCommit = { [weak self, weak collectionView] in
                guard let self,
                      let collectionView,
                      self.contentCommitGeneration == commitGeneration
                else { return }

                if self.layout?.needsLayoutUpdate == true {
                    UIView.performWithoutAnimation {
                        collectionView.collectionViewLayout.invalidateLayout()
                        collectionView.layoutIfNeeded()
                    }
                }

                let isRefreshing =
                    collectionView.refreshControl?.isRefreshing == true
                let isScrolling = self.isActivelyScrolling(collectionView)
                if !isRefreshing, !isScrolling {
                    if replacesDataset {
                        self.resetScrollPositionAfterLayout(in: collectionView)
                    } else if needsLayoutUpdate {
                        self.restoreAfterLayout(anchor: anchor, in: collectionView)
                    }
                }

                self.pendingContentCommitGeneration = nil
                self.scheduleDeferredContentUpdateIfPossible()
                self.reconcileRefreshAfterWorkDrained()
                self.flushMeasuredHeightsIfPossible()
                self.fetchMoreIfNeeded(in: collectionView)
            }

            if requiresSnapshotCommit {
                var snapshot = NSDiffableDataSourceSnapshot<WaterfallSection, WaterfallItemID>()
                snapshot.appendSections([.main])
                snapshot.appendItems(newItemIdentifiers)
                if replacesDataset || structureChanged {
                    dataSource.applySnapshotUsingReloadData(
                        snapshot,
                        completion: finishContentCommit
                    )
                } else {
                    snapshot.reconfigureItems(Array(identifiersToReconfigure))
                    dataSource.apply(
                        snapshot,
                        animatingDifferences: false,
                        completion: finishContentCommit
                    )
                }
            } else {
                finishContentCommit()
            }
        }

        func tearDown() {
            refreshTask?.cancel()
            refreshTask = nil
            refreshStateMachine.cancel()
            refreshHasPendingTerminalContent = false
            deferredContentParent = nil
            deferredContentUpdateIsScheduled = false
            lifecycleGeneration &+= 1
            contentCommitGeneration &+= 1
            pendingContentCommitGeneration = nil
            scrollOperationGeneration &+= 1
            pendingResetGeneration = nil
            prefetchers.values.forEach { $0.prefetcher.stop() }
            prefetchers.removeAll()
            pendingMeasuredHeights.removeAll()
        }
    }
}

private extension WaterfallCollectionView.Coordinator {
    func configure(
        cell: WaterfallHostingCell,
        at indexPath: IndexPath,
        itemIdentifier: WaterfallItemID
    ) {
        let measurementGeneration = measurementGenerations[itemIdentifier, default: 0]
        cell.prepare(for: itemIdentifier) { [weak self] identifier, height, width in
            self?.queueMeasuredHeight(
                height,
                measuredAtWidth: width,
                for: identifier,
                generation: measurementGeneration
            )
        }
        cell.backgroundConfiguration = .clear()
        cell.clipsToBounds = true

        switch itemIdentifier {
        case .gallery(let id):
            guard let gallery = galleriesByID[id] else {
                cell.contentConfiguration = nil
                return
            }
            let itemWidth =
                layout?.layoutAttributesForItem(at: indexPath)?.size.width
                ?? layout?.currentItemWidth
                ?? Defaults.ImageSize.rowW * 2
            let setting = parent.setting
            let environment = environment
            let contextMenuConfiguration = parent.galleryContextMenuConfiguration
            let presentation = presentationsByID[id]
            let actions = parent.actionsProvider?(id) ?? []
            let translateAction: (String) -> (String, TagTranslation?) = { [weak self] word in
                self?.parent.translateAction?(word) ?? (word, nil)
            }

            cell.contentConfiguration = UIHostingConfiguration {
                GalleryThumbnailCell(
                    gallery: gallery,
                    setting: setting,
                    availableWidth: itemWidth,
                    informationHeight: GalleryThumbnailCell.informationHeight(
                        gallery: gallery,
                        setting: setting,
                        availableWidth: itemWidth,
                        presentation: presentation,
                        translateAction: translateAction
                    ),
                    presentation: presentation,
                    actions: actions,
                    translateAction: translateAction
                )
                .multilineTextAlignment(.leading)
                .galleryContextMenu(gallery: gallery, actions: actions)
                .environment(\.colorScheme, environment.colorScheme)
                .environment(\.dynamicTypeSize, environment.dynamicTypeSize)
                .environment(\.inSheet, environment.inSheet)
                .environment(
                    \.isStandaloneGalleryWindow,
                    environment.isStandaloneGalleryWindow
                )
                .environment(\.layoutDirection, environment.layoutDirection)
                .environment(\.locale, environment.locale)
                .environment(
                    \.galleryContextMenuConfiguration,
                    contextMenuConfiguration
                )
            }
            .margins(.all, 0)

            cell.isAccessibilityElement = true
            cell.accessibilityLabel = gallery.title
            cell.accessibilityValue = [
                gallery.category.value,
                gallery.language?.value,
                L10n.Localizable.Common.Value.pages(gallery.pageCount),
                "\(L10n.Localizable.GalleryInfosView.Title.averageRating) \(gallery.rating)"
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
            cell.accessibilityTraits = [.button]
            cell.activationAction = { [weak self] in
                self?.parent.navigateAction?(id)
            }

        case .footer:
            let loadingState = parent.footerLoadingState
            let retryAction: () -> Void = { [weak self] in
                self?.parent.fetchMoreAction?()
            }

            cell.contentConfiguration = UIHostingConfiguration {
                if loadingState == .idle {
                    Color.clear
                        .frame(height: 1)
                        .accessibilityHidden(true)
                } else {
                    FetchMoreFooter(
                        loadingState: loadingState,
                        retryAction: retryAction
                    )
                }
            }
            .margins(.all, 0)

            cell.isAccessibilityElement = false
            cell.accessibilityLabel = nil
            cell.accessibilityValue = nil
            cell.accessibilityTraits = []
            cell.activationAction = nil
        }
    }

    func queueMeasuredHeight(
        _ height: CGFloat,
        measuredAtWidth width: CGFloat,
        for itemIdentifier: WaterfallItemID,
        generation: Int
    ) {
        // Gallery cards have a deterministic cover and information height. Applying
        // delayed SwiftUI measurements would move every item below the measured card.
        guard itemIdentifier == .footer else { return }
        guard height.isFinite,
              height > 0,
              width.isFinite,
              width > 0,
              measurementGenerations[itemIdentifier] == generation
        else { return }

        pendingMeasuredHeights[itemIdentifier] = .init(
            height: ceil(height),
            width: width,
            generation: generation
        )
        guard !schedulesHeightUpdate else { return }

        schedulesHeightUpdate = true
        DispatchQueue.main.async { [weak self] in
            self?.flushMeasuredHeightsIfPossible()
        }
    }

    func flushMeasuredHeightsIfPossible() {
        schedulesHeightUpdate = false
        guard let collectionView, let layout else {
            pendingMeasuredHeights.removeAll()
            return
        }
        guard !isActivelyScrolling(collectionView),
              pendingContentCommitGeneration == nil,
              deferredContentParent == nil
        else { return }

        var measurements = [WaterfallItemID: CGFloat]()
        for (identifier, measurement) in pendingMeasuredHeights
        where measurementGenerations[identifier] == measurement.generation
            && layout.acceptsMeasuredWidth(measurement.width, for: identifier) {
            measurements[identifier] = measurement.height
        }
        pendingMeasuredHeights.removeAll()
        guard !measurements.isEmpty else { return }
        guard layout.updateMeasuredHeights(measurements) else { return }

        let anchor = captureAnchor(in: collectionView)
        layout.invalidateLayout()
        restoreAfterLayout(anchor: anchor, in: collectionView)
        fetchMoreIfNeeded(in: collectionView)
    }

    func invalidatePendingMeasurements(for identifiers: Set<WaterfallItemID>) {
        for identifier in identifiers {
            measurementGenerations[identifier, default: 0] &+= 1
            pendingMeasuredHeights[identifier] = nil
        }
    }

    func shouldDeferContentUpdate(
        for parent: WaterfallCollectionView,
        in collectionView: UICollectionView
    ) -> Bool {
        let isScrolling = isActivelyScrolling(collectionView)
        let hasPendingCommit = pendingContentCommitGeneration != nil
        guard isScrolling || hasPendingCommit
        else { return false }

        let loadingStateChanged = loadingState != parent.loadingState
        let contentChanged: Bool
        if settingSignature != .init(setting: parent.setting)
            || environment != parent.hostEnvironment
            || translationRevision != parent.translationRevision
            || datasetIdentity != parent.datasetIdentity
            || footerLoadingState != parent.footerLoadingState
            || refreshRevision != parent.refreshRevision
        {
            contentChanged = true
        } else {
            var identifiers = [WaterfallItemID]()
            var signatures = [String: GalleryRenderSignature]()
            var presentations = [String: GalleryListPresentation]()
            var seenIDs = Set<String>()
            for gallery in parent.galleries where seenIDs.insert(gallery.id).inserted {
                identifiers.append(.gallery(gallery.id))
                signatures[gallery.id] = .init(gallery: gallery)
                presentations[gallery.id] = parent.presentations[gallery.id]
            }
            if parent.pageNumber?.hasNextPage() == true {
                identifiers.append(.footer)
            }

            contentChanged =
                identifiers != itemIdentifiers
                || signatures != gallerySignatures
                || presentations != presentationsByID
        }

        return WaterfallContentCommitGate.shouldDefer(
            contentChanged: contentChanged,
            loadingStateChanged: loadingStateChanged,
            isActivelyScrolling: isScrolling,
            hasPendingCommit: hasPendingCommit
        )
    }

    @objc func refresh() {
        guard let fetchAction = parent.fetchAction else {
            collectionView?.refreshControl?.endRefreshing()
            return
        }
        guard parent.loadingState != .loading else {
            collectionView?.refreshControl?.endRefreshing()
            return
        }
        guard refreshStateMachine.begin() else { return }

        refreshHasPendingTerminalContent = false
        cancelScheduledScrollRestore()
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            await fetchAction()
            guard !Task.isCancelled, let self else { return }
            self.refreshTask = nil
            self.refreshOperationDidComplete()
        }
    }

    func refreshOperationDidComplete() {
        guard let collectionView else { return }
        let isScrolling = isActivelyScrolling(collectionView)
        if !isScrolling {
            scheduleDeferredContentUpdateIfPossible()
        }
        if refreshStateMachine.operationCompleted(isScrolling: isScrolling) {
            endRefreshing()
        }
    }

    func refreshContentDidCommit(loadingState: LoadingState) {
        guard let collectionView else { return }
        if refreshStateMachine.contentDidCommit(
            isLoading: loadingState == .loading,
            isScrolling: isActivelyScrolling(collectionView)
        ) {
            endRefreshing()
        }
    }

    func scrollingDidEnd() {
        scheduleDeferredContentUpdateIfPossible()
        reconcileRefreshAfterWorkDrained()
    }

    func endRefreshing() {
        refreshHasPendingTerminalContent = false
        collectionView?.refreshControl?.endRefreshing()
    }

    func completeRefreshTerminalContentIfPossible() {
        guard refreshHasPendingTerminalContent,
              pendingContentCommitGeneration == nil,
              deferredContentParent == nil,
              loadingState != .loading
        else { return }

        refreshHasPendingTerminalContent = false
        refreshContentDidCommit(loadingState: loadingState)
    }

    func scheduleDeferredContentUpdateIfPossible() {
        guard !deferredContentUpdateIsScheduled,
              deferredContentParent != nil,
              pendingContentCommitGeneration == nil,
              let collectionView,
              !isActivelyScrolling(collectionView)
        else { return }

        deferredContentUpdateIsScheduled = true
        let generation = lifecycleGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.lifecycleGeneration == generation else { return }
            self.deferredContentUpdateIsScheduled = false
            self.applyDeferredContentUpdateIfPossible()
        }
    }

    func applyDeferredContentUpdateIfPossible() {
        guard let collectionView,
              pendingContentCommitGeneration == nil,
              !isActivelyScrolling(collectionView),
              let deferredContentParent
        else { return }

        self.deferredContentParent = nil
        update(parent: deferredContentParent, collectionView: collectionView)
        flushMeasuredHeightsIfPossible()

        guard pendingContentCommitGeneration == nil,
              self.deferredContentParent == nil
        else { return }
        reconcileRefreshAfterWorkDrained()
    }

    func reconcileRefreshAfterWorkDrained() {
        guard let collectionView,
              pendingContentCommitGeneration == nil,
              deferredContentParent == nil,
              !isActivelyScrolling(collectionView)
        else { return }

        completeRefreshTerminalContentIfPossible()
        if refreshStateMachine.scrollingDidEnd() {
            endRefreshing()
        }
    }

    func fetchMoreIfNeeded(in collectionView: UICollectionView) {
        guard deferredContentParent == nil,
              pendingContentCommitGeneration == nil,
              parent.loadingState == .idle,
              parent.pageNumber?.hasNextPage() == true,
              parent.footerLoadingState == .idle,
              parent.fetchMoreAction != nil
        else { return }

        let visibleBottom =
            collectionView.contentOffset.y
            + collectionView.bounds.height
            - collectionView.adjustedContentInset.bottom
        let preloadDistance = max(collectionView.bounds.height * 0.4, 240)
        guard collectionView.contentSize.height <= visibleBottom + preloadDistance else { return }

        let trigger = PaginationTrigger(
            pageNumber: parent.pageNumber,
            galleryCount: parent.galleries.count,
            firstGalleryID: parent.galleries.first?.id,
            lastGalleryID: parent.galleries.last?.id
        )
        guard lastPaginationTrigger != trigger else { return }
        lastPaginationTrigger = trigger
        parent.fetchMoreAction?()
    }

    func captureAnchor(in collectionView: UICollectionView) -> WaterfallScrollAnchor? {
        guard collectionView.refreshControl?.isRefreshing != true,
              !isActivelyScrolling(collectionView),
              let layout
        else { return nil }

        let visibleTop = collectionView.contentOffset.y + collectionView.adjustedContentInset.top
        let visibleRect = CGRect(
            x: collectionView.contentOffset.x,
            y: visibleTop,
            width: collectionView.bounds.width,
            height: collectionView.bounds.height
        )
        let attributes = layout.layoutAttributesForElements(in: visibleRect) ?? []
        let anchorAttributes = attributes
            .filter {
                guard let identifier = layout.itemIdentifier(at: $0.indexPath),
                      case .gallery = identifier
                else { return false }
                return $0.frame.maxY >= visibleTop
            }
            .min {
                if $0.frame.minY == $1.frame.minY {
                    return $0.frame.minX < $1.frame.minX
                }
                return $0.frame.minY < $1.frame.minY
            }
        guard let anchorAttributes,
              let identifier = layout.itemIdentifier(at: anchorAttributes.indexPath)
        else { return nil }

        return .init(
            itemIdentifier: identifier,
            offsetFromVisibleTop: visibleTop - anchorAttributes.frame.minY,
            adjustedContentInsetTop: collectionView.adjustedContentInset.top
        )
    }

    func restoreAfterLayout(
        anchor: WaterfallScrollAnchor?,
        in collectionView: UICollectionView
    ) {
        guard pendingResetGeneration == nil,
              let anchor,
              abs(
                anchor.adjustedContentInsetTop
                    - collectionView.adjustedContentInset.top
              ) <= 0.5
        else { return }

        scrollOperationGeneration &+= 1
        let generation = scrollOperationGeneration
        DispatchQueue.main.async { [weak self, weak collectionView] in
            guard let self,
                  let collectionView,
                  self.scrollOperationGeneration == generation,
                  !self.isActivelyScrolling(collectionView),
                  abs(
                    anchor.adjustedContentInsetTop
                        - collectionView.adjustedContentInset.top
                  ) <= 0.5
            else { return }

            collectionView.layoutIfNeeded()
            self.restore(anchor: anchor, in: collectionView)
        }
    }

    func cancelScheduledScrollRestore() {
        scrollOperationGeneration &+= 1
        pendingResetGeneration = nil
    }

    func resetScrollPositionAfterLayout(in collectionView: UICollectionView) {
        scrollOperationGeneration &+= 1
        let generation = scrollOperationGeneration
        pendingResetGeneration = generation

        DispatchQueue.main.async { [weak self, weak collectionView] in
            guard let self,
                  let collectionView,
                  self.scrollOperationGeneration == generation,
                  self.pendingResetGeneration == generation
            else { return }

            guard !self.isActivelyScrolling(collectionView),
                  collectionView.refreshControl?.isRefreshing != true
            else {
                self.pendingResetGeneration = nil
                return
            }

            UIView.performWithoutAnimation {
                collectionView.layoutIfNeeded()
                collectionView.setContentOffset(
                    CGPoint(
                        x: collectionView.contentOffset.x,
                        y: -collectionView.adjustedContentInset.top
                    ),
                    animated: false
                )
            }
            self.pendingResetGeneration = nil
        }
    }

    func restore(anchor: WaterfallScrollAnchor, in collectionView: UICollectionView) {
        guard abs(
            anchor.adjustedContentInsetTop
                - collectionView.adjustedContentInset.top
        ) <= 0.5,
              let layout,
              let indexPath = layout.indexPath(for: anchor.itemIdentifier),
              let attributes = layout.layoutAttributesForItem(at: indexPath)
        else { return }

        let proposedOffset =
            attributes.frame.minY
            + anchor.offsetFromVisibleTop
            - collectionView.adjustedContentInset.top
        let minimumOffset = -collectionView.adjustedContentInset.top
        let maximumOffset = max(
            minimumOffset,
            collectionView.contentSize.height
                - collectionView.bounds.height
                + collectionView.adjustedContentInset.bottom
        )
        collectionView.setContentOffset(
            CGPoint(
                x: collectionView.contentOffset.x,
                y: min(max(proposedOffset, minimumOffset), maximumOffset)
            ),
            animated: false
        )
    }

    func isActivelyScrolling(_ collectionView: UICollectionView) -> Bool {
        collectionView.isTracking
            || collectionView.isDragging
            || collectionView.isDecelerating
    }

    func startPrefetching(galleryID: String, url: URL, targetSize: CGSize) {
        guard prefetchers[galleryID] == nil else { return }

        let token = UUID()
        let processor = DownsamplingImageProcessor(size: targetSize)
        var options: KingfisherOptionsInfo = [
            .processor(processor),
            .backgroundDecode
        ]
        if url.isFileURL {
            options.append(.cacheMemoryOnly)
        }
        let prefetcher = ImagePrefetcher(
            urls: [url],
            options: options
        ) { [weak self] _, _, _ in
            DispatchQueue.main.async { [weak self] in
                guard self?.prefetchers[galleryID]?.token == token else { return }
                self?.prefetchers[galleryID] = nil
            }
        }
        prefetchers[galleryID] = .init(token: token, prefetcher: prefetcher)
        prefetcher.start()
    }
}

extension WaterfallCollectionView.Coordinator:
    UICollectionViewDelegate,
    UICollectionViewDataSourcePrefetching
{
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let itemIdentifier = dataSource.itemIdentifier(for: indexPath),
              case .gallery(let id) = itemIdentifier
        else { return }
        collectionView.deselectItem(at: indexPath, animated: false)
        parent.navigateAction?(id)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        if dataSource.itemIdentifier(for: indexPath) == .footer {
            fetchMoreIfNeeded(in: collectionView)
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard let collectionView = scrollView as? UICollectionView else { return }
        fetchMoreIfNeeded(in: collectionView)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        cancelScheduledScrollRestore()
    }

    func scrollViewDidChangeAdjustedContentInset(_ scrollView: UIScrollView) {
        cancelScheduledScrollRestore()
        pendingBoundsChangeAnchor = nil
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !decelerate else { return }
        scrollingDidEnd()
        flushMeasuredHeightsIfPossible()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        scrollingDidEnd()
        flushMeasuredHeightsIfPossible()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        scrollingDidEnd()
        flushMeasuredHeightsIfPossible()
    }

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        guard let layout else { return }

        let scale = collectionView.traitCollection.displayScale
        let width = max(layout.currentItemWidth, Defaults.ImageSize.rowW)
        let targetSize = CGSize(
            width: width * scale,
            height: width / Defaults.ImageSize.webtoonMinAspect * scale
        )

        for indexPath in indexPaths {
            guard let itemIdentifier = dataSource.itemIdentifier(for: indexPath),
                  case .gallery(let id) = itemIdentifier,
                  let url = presentationsByID[id]?.coverURL
                    ?? galleriesByID[id]?.coverURL
            else { continue }
            startPrefetching(galleryID: id, url: url, targetSize: targetSize)
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cancelPrefetchingForItemsAt indexPaths: [IndexPath]
    ) {
        for indexPath in indexPaths {
            guard let itemIdentifier = dataSource.itemIdentifier(for: indexPath),
                  case .gallery(let id) = itemIdentifier
            else { continue }
            prefetchers[id]?.prefetcher.stop()
            prefetchers[id] = nil
        }
    }
}

private enum WaterfallSection {
    case main
}

enum WaterfallItemID: Hashable {
    case gallery(String)
    case footer
}

enum WaterfallDatasetUpdateKind: Equatable {
    case initial
    case unchanged
    case append
    case replace

    static func classify(
        oldIdentifiers: [WaterfallItemID],
        newIdentifiers: [WaterfallItemID],
        hasExistingSnapshot: Bool,
        datasetChanged: Bool
    ) -> Self {
        guard hasExistingSnapshot else { return .initial }
        guard !datasetChanged else { return .replace }
        guard oldIdentifiers != newIdentifiers else { return .unchanged }

        let oldGalleryCount = oldIdentifiers.last == .footer
            ? oldIdentifiers.count - 1
            : oldIdentifiers.count
        let newGalleryCount = newIdentifiers.last == .footer
            ? newIdentifiers.count - 1
            : newIdentifiers.count
        guard newGalleryCount >= oldGalleryCount,
              oldIdentifiers.prefix(oldGalleryCount)
                .elementsEqual(newIdentifiers.prefix(oldGalleryCount))
        else { return .replace }
        return .append
    }
}

struct WaterfallContentCommitGate {
    static func shouldDefer(
        contentChanged: Bool,
        loadingStateChanged: Bool = false,
        isActivelyScrolling: Bool,
        hasPendingCommit: Bool
    ) -> Bool {
        hasPendingCommit
            || ((contentChanged || loadingStateChanged) && isActivelyScrolling)
    }
}

struct GalleryRefreshStateMachine {
    enum Phase: Equatable {
        case idle
        case refreshing
        case waitingForContent
        case waitingForScrollEnd
    }

    private(set) var phase: Phase = .idle
    private var operationHasCompleted = false
    private var contentHasCommitted = false

    mutating func begin() -> Bool {
        guard phase == .idle else { return false }
        operationHasCompleted = false
        contentHasCommitted = false
        phase = .refreshing
        return true
    }

    mutating func operationCompleted(isScrolling: Bool) -> Bool {
        guard phase != .idle, !operationHasCompleted else { return false }
        operationHasCompleted = true
        guard contentHasCommitted else {
            phase = .waitingForContent
            return false
        }
        return finishIfPossible(isScrolling: isScrolling)
    }

    mutating func contentDidCommit(
        isLoading: Bool,
        isScrolling: Bool
    ) -> Bool {
        guard phase != .idle else { return false }
        if isLoading {
            contentHasCommitted = false
            phase = operationHasCompleted ? .waitingForContent : .refreshing
            return false
        }
        contentHasCommitted = true
        guard operationHasCompleted else { return false }
        return finishIfPossible(isScrolling: isScrolling)
    }

    mutating func scrollingDidEnd() -> Bool {
        guard phase == .waitingForScrollEnd,
              operationHasCompleted,
              contentHasCommitted
        else { return false }
        phase = .idle
        return true
    }

    mutating func cancel() {
        operationHasCompleted = false
        contentHasCommitted = false
        phase = .idle
    }

    private mutating func finishIfPossible(isScrolling: Bool) -> Bool {
        if isScrolling {
            phase = .waitingForScrollEnd
            return false
        }
        phase = .idle
        return true
    }
}

private struct WaterfallPendingMeasurement {
    let height: CGFloat
    let width: CGFloat
    let generation: Int
}

private struct WaterfallPrefetchTask {
    let token: UUID
    let prefetcher: ImagePrefetcher
}

private struct PaginationTrigger: Equatable {
    let pageNumber: PageNumber?
    let galleryCount: Int
    let firstGalleryID: String?
    let lastGalleryID: String?
}

private struct WaterfallScrollAnchor {
    let itemIdentifier: WaterfallItemID
    let offsetFromVisibleTop: CGFloat
    let adjustedContentInsetTop: CGFloat
}

private struct WaterfallHostEnvironment: Equatable {
    let colorScheme: ColorScheme
    let dynamicTypeSize: DynamicTypeSize
    let inSheet: Bool
    let isStandaloneGalleryWindow: Bool
    let layoutDirection: LayoutDirection
    let locale: Locale
}

private struct WaterfallSettingSignature: Equatable {
    let showsTagsInList: Bool
    let listTagsNumberMaximum: Int
    let showsImagesInTags: Bool
    let translatesTags: Bool

    init(setting: Setting) {
        showsTagsInList = setting.showsTagsInList
        listTagsNumberMaximum = setting.listTagsNumberMaximum
        showsImagesInTags = setting.showsImagesInTags
        translatesTags = setting.translatesTags
    }
}

private struct GalleryRenderSignature: Equatable {
    let title: String
    let rating: Float
    let tags: [GalleryTag]
    let category: Category
    let uploader: String?
    let pageCount: Int
    let postedDate: Date
    let coverURL: URL?

    init(gallery: Gallery) {
        title = gallery.title
        rating = gallery.rating
        tags = gallery.tags
        category = gallery.category
        uploader = gallery.uploader
        pageCount = gallery.pageCount
        postedDate = gallery.postedDate
        coverURL = gallery.coverURL
    }
}

private final class WaterfallUICollectionView: UICollectionView {
    var boundsSizeWillChangeAction: (() -> Void)?
    var boundsSizeDidChangeAction: (() -> Void)?

    override var bounds: CGRect {
        willSet {
            if abs(newValue.width - bounds.width) > 0.5 {
                boundsSizeWillChangeAction?()
            }
        }
        didSet {
            if abs(oldValue.width - bounds.width) > 0.5 {
                boundsSizeDidChangeAction?()
            }
        }
    }
}

private final class WaterfallHostingCell: UICollectionViewCell {
    private var itemIdentifier: WaterfallItemID?
    private var lastReportedHeight: CGFloat?
    private var lastReportedWidth: CGFloat?
    private var heightAction: ((WaterfallItemID, CGFloat, CGFloat) -> Void)?

    var activationAction: (() -> Void)?

    func prepare(
        for itemIdentifier: WaterfallItemID,
        heightAction: @escaping (WaterfallItemID, CGFloat, CGFloat) -> Void
    ) {
        self.itemIdentifier = itemIdentifier
        self.heightAction = heightAction
        lastReportedHeight = nil
        lastReportedWidth = nil
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        if itemIdentifier == .footer {
            _ = measureAndReport(width: layoutAttributes.size.width)
        }
        return layoutAttributes
    }

    override func accessibilityActivate() -> Bool {
        guard let activationAction else { return false }
        activationAction()
        return true
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        itemIdentifier = nil
        lastReportedHeight = nil
        lastReportedWidth = nil
        heightAction = nil
        activationAction = nil
        isAccessibilityElement = false
        accessibilityLabel = nil
        accessibilityValue = nil
        accessibilityTraits = []
        contentConfiguration = nil
    }

    private func measureAndReport(width: CGFloat) -> CGFloat {
        guard width > 0 else { return 1 }

        contentView.bounds.size.width = width
        contentView.setNeedsLayout()
        contentView.layoutIfNeeded()

        let measuredSize = contentView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let measuredHeight = max(1, ceil(measuredSize.height))
        let heightChanged =
            lastReportedHeight.map { abs($0 - measuredHeight) > 0.5 } ?? true
        let widthChanged =
            lastReportedWidth.map { abs($0 - width) > 0.5 } ?? true
        if heightChanged || widthChanged,
           let itemIdentifier
        {
            lastReportedHeight = measuredHeight
            lastReportedWidth = width
            heightAction?(itemIdentifier, measuredHeight, width)
        }
        return measuredHeight
    }
}

struct WaterfallLayoutItem {
    let height: CGFloat
    let spansAllColumns: Bool
}

struct WaterfallLayoutResult {
    let frames: [CGRect]
    let contentHeight: CGFloat
}

private struct WaterfallLayoutState {
    var columnBottoms: [CGFloat]
    var hasPlacedItem: Bool

    func isApproximatelyEqual(to other: Self) -> Bool {
        guard hasPlacedItem == other.hasPlacedItem,
              columnBottoms.count == other.columnBottoms.count
        else { return false }

        return zip(columnBottoms, other.columnBottoms)
            .allSatisfy { abs($0 - $1) <= 0.25 }
    }
}

enum WaterfallLayoutCalculator {
    static func calculate(
        containerWidth: CGFloat,
        columnCount: Int,
        spacing: CGFloat,
        sectionInsets: UIEdgeInsets,
        items: [WaterfallLayoutItem],
        columnAssignments: [Int?]? = nil
    ) -> WaterfallLayoutResult {
        guard containerWidth > 0, columnCount > 0 else {
            return .init(frames: [], contentHeight: 0)
        }

        let availableWidth = max(
            0,
            containerWidth
                - sectionInsets.left
                - sectionInsets.right
                - CGFloat(columnCount - 1) * spacing
        )
        let itemWidth = availableWidth / CGFloat(columnCount)
        var state = initialState(columnCount: columnCount, sectionInsets: sectionInsets)
        var frames = [CGRect]()

        for (index, item) in items.enumerated() {
            let assignedColumn = columnAssignments.flatMap {
                $0.indices.contains(index) ? $0[index] : nil
            }
            frames.append(
                place(
                    item: item,
                    containerWidth: containerWidth,
                    itemWidth: itemWidth,
                    spacing: spacing,
                    sectionInsets: sectionInsets,
                    columnIndex: assignedColumn,
                    state: &state
                )
            )
        }

        let contentHeight = items.isEmpty
            ? 0
            : (state.columnBottoms.max() ?? 0) + sectionInsets.bottom
        return .init(frames: frames, contentHeight: contentHeight)
    }

    fileprivate static func initialState(
        columnCount: Int,
        sectionInsets: UIEdgeInsets
    ) -> WaterfallLayoutState {
        .init(
            columnBottoms: Array(repeating: sectionInsets.top, count: columnCount),
            hasPlacedItem: false
        )
    }

    fileprivate static func place(
        item: WaterfallLayoutItem,
        containerWidth: CGFloat,
        itemWidth: CGFloat,
        spacing: CGFloat,
        sectionInsets: UIEdgeInsets,
        columnIndex preferredColumnIndex: Int? = nil,
        state: inout WaterfallLayoutState
    ) -> CGRect {
        let height = max(1, item.height)
        let frame: CGRect
        if item.spansAllColumns {
            let currentBottom = state.columnBottoms.max() ?? sectionInsets.top
            let y = currentBottom + (state.hasPlacedItem ? spacing : 0)
            frame = CGRect(
                x: sectionInsets.left,
                y: y,
                width: max(0, containerWidth - sectionInsets.left - sectionInsets.right),
                height: height
            )
            state.columnBottoms = Array(repeating: frame.maxY, count: state.columnBottoms.count)
        } else {
            let columnIndex = preferredColumnIndex.flatMap {
                state.columnBottoms.indices.contains($0) ? $0 : nil
            } ?? shortestColumnIndex(in: state)
            let columnBottom = state.columnBottoms[columnIndex]
            let y = columnBottom
                + (state.hasPlacedItem && columnBottom > sectionInsets.top ? spacing : 0)
            let x = sectionInsets.left + CGFloat(columnIndex) * (itemWidth + spacing)
            frame = CGRect(x: x, y: y, width: itemWidth, height: height)
            state.columnBottoms[columnIndex] = frame.maxY
        }
        state.hasPlacedItem = true
        return frame
    }

    fileprivate static func shortestColumnIndex(in state: WaterfallLayoutState) -> Int {
        let shortestBottom = state.columnBottoms.min() ?? 0
        return state.columnBottoms.firstIndex(of: shortestBottom) ?? 0
    }
}

final class WaterfallCollectionLayout: UICollectionViewLayout {
    private static let spatialBucketHeight: CGFloat = 512

    private var itemIdentifiers = [WaterfallItemID]()
    private var indexPathsByIdentifier = [WaterfallItemID: IndexPath]()
    private var measuredHeights = [WaterfallItemID: CGFloat]()
    private var columnAssignments = [WaterfallItemID: Int]()
    private var itemAttributes = [UICollectionViewLayoutAttributes]()
    private var statesAfterItems = [WaterfallLayoutState]()
    private var itemIndexesByVerticalBucket = [Int: [Int]]()
    private var calculatedContentSize = CGSize.zero
    private var lastBoundsWidth = CGFloat.zero
    private var lastColumnCount = 0
    private var lastSectionInsets = UIEdgeInsets.zero
    private var lastDisplayScale = CGFloat.zero
    private var invalidFromIndex: Int? = 0
    private var invalidThroughIndex = 0

    private var estimatedGalleryExtraHeight: CGFloat = 125
    private var estimatedGalleryExtraHeightProvider:
        ((WaterfallItemID, CGFloat) -> CGFloat)?
    private var estimatedFooterHeight: CGFloat = 1

    private(set) var currentItemWidth: CGFloat = 0
    private(set) var currentFullWidth: CGFloat = 0
    var needsLayoutUpdate: Bool { invalidFromIndex != nil }

    override var collectionViewContentSize: CGSize {
        calculatedContentSize
    }

    override var flipsHorizontallyInOppositeLayoutDirection: Bool {
        true
    }

    func setItems(
        _ newItemIdentifiers: [WaterfallItemID],
        estimatedGalleryExtraHeight newGalleryExtraHeight: CGFloat,
        estimatedGalleryExtraHeightProvider newGalleryExtraHeightProvider:
            ((WaterfallItemID, CGFloat) -> CGFloat)? = nil,
        estimatedFooterHeight newFooterHeight: CGFloat
    ) {
        estimatedGalleryExtraHeightProvider = newGalleryExtraHeightProvider
        if itemIdentifiers != newItemIdentifiers {
            let commonPrefixCount = zip(itemIdentifiers, newItemIdentifiers)
                .prefix { $0.0 == $0.1 }
                .count
            let affectedCount = max(itemIdentifiers.count, newItemIdentifiers.count)
            markInvalid(
                from: commonPrefixCount,
                through: max(commonPrefixCount, affectedCount - 1)
            )

            itemIdentifiers = newItemIdentifiers
            let validIdentifiers = Set(newItemIdentifiers)
            measuredHeights = measuredHeights.filter { validIdentifiers.contains($0.key) }
            columnAssignments = columnAssignments.filter {
                validIdentifiers.contains($0.key)
            }
            indexPathsByIdentifier = Dictionary(
                uniqueKeysWithValues: newItemIdentifiers.enumerated().map {
                    ($0.element, IndexPath(item: $0.offset, section: 0))
                }
            )
        }

        if abs(estimatedGalleryExtraHeight - newGalleryExtraHeight) > 0.5 {
            estimatedGalleryExtraHeight = newGalleryExtraHeight
            if let index = itemIdentifiers.firstIndex(where: {
                if case .gallery = $0 { return measuredHeights[$0] == nil }
                return false
            }) {
                markInvalid(from: index, through: max(index, itemIdentifiers.count - 1))
            }
        }
        if abs(estimatedFooterHeight - newFooterHeight) > 0.5 {
            estimatedFooterHeight = newFooterHeight
            if let index = indexPathsByIdentifier[.footer]?.item,
               measuredHeights[.footer] == nil
            {
                markInvalid(from: index, through: index)
            }
        }
    }

    func updateMeasuredHeights(_ heights: [WaterfallItemID: CGFloat]) -> Bool {
        var affectedIndices = [Int]()
        for (identifier, height) in heights where height.isFinite && height > 0 {
            guard measuredHeights[identifier].map({ abs($0 - height) > 0.5 }) ?? true,
                  let index = indexPathsByIdentifier[identifier]?.item
            else { continue }

            measuredHeights[identifier] = height
            affectedIndices.append(index)
        }
        if let first = affectedIndices.min(), let last = affectedIndices.max() {
            markInvalid(from: first, through: last)
        }
        return !affectedIndices.isEmpty
    }

    func removeMeasuredHeights(for identifiers: [WaterfallItemID]) {
        let affectedIndices = identifiers.compactMap { identifier -> Int? in
            guard measuredHeights.removeValue(forKey: identifier) != nil else { return nil }
            return indexPathsByIdentifier[identifier]?.item
        }
        if let first = affectedIndices.min(), let last = affectedIndices.max() {
            markInvalid(from: first, through: last)
        }
    }

    func removeAllMeasuredHeights() {
        guard !measuredHeights.isEmpty else { return }
        let affectedIndices = measuredHeights.keys.compactMap {
            indexPathsByIdentifier[$0]?.item
        }
        measuredHeights.removeAll()
        if let first = affectedIndices.min(), let last = affectedIndices.max() {
            markInvalid(from: first, through: last)
        }
    }

    func invalidateEstimatedHeights(for identifiers: Set<WaterfallItemID>) {
        let affectedIndices = identifiers.compactMap {
            indexPathsByIdentifier[$0]?.item
        }
        guard let first = affectedIndices.min() else { return }
        markInvalid(from: first, through: max(first, itemIdentifiers.count - 1))
    }

    func itemIdentifier(at indexPath: IndexPath) -> WaterfallItemID? {
        guard indexPath.section == 0, itemIdentifiers.indices.contains(indexPath.item) else {
            return nil
        }
        return itemIdentifiers[indexPath.item]
    }

    func indexPath(for itemIdentifier: WaterfallItemID) -> IndexPath? {
        indexPathsByIdentifier[itemIdentifier]
    }

    func resetColumnAssignments() {
        guard !columnAssignments.isEmpty else { return }
        columnAssignments.removeAll()
        markInvalid(from: 0, through: max(0, itemIdentifiers.count - 1))
    }

    func acceptsMeasuredWidth(_ width: CGFloat, for itemIdentifier: WaterfallItemID) -> Bool {
        let expectedWidth = itemIdentifier == .footer
            ? currentFullWidth
            : currentItemWidth
        return expectedWidth > 0 && abs(width - expectedWidth) <= 0.5
    }

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }

        let bounds = collectionView.bounds
        let columnCount = Self.columnCount(for: bounds, collectionView: collectionView)
        let sectionInsets = Self.sectionInsets(for: bounds)
        let displayScale = max(collectionView.traitCollection.displayScale, 1)
        let geometryChanged =
            abs(lastBoundsWidth - bounds.width) > 0.5
            || lastColumnCount != columnCount
            || lastSectionInsets != sectionInsets
            || abs(lastDisplayScale - displayScale) > 0.01
        if geometryChanged {
            measuredHeights.removeAll()
            if lastColumnCount != 0, lastColumnCount != columnCount {
                columnAssignments.removeAll()
            }
            markInvalid(from: 0, through: max(0, itemIdentifiers.count - 1))
        }

        lastBoundsWidth = bounds.width
        lastColumnCount = columnCount
        lastSectionInsets = sectionInsets
        lastDisplayScale = displayScale
        let availableWidth = max(
            0,
            bounds.width
                - sectionInsets.left
                - sectionInsets.right
                - CGFloat(columnCount - 1) * Self.spacing
        )
        let rawItemWidth = availableWidth / CGFloat(max(columnCount, 1))
        currentItemWidth = floor(rawItemWidth * displayScale) / displayScale
        currentFullWidth = max(
            0,
            bounds.width - sectionInsets.left - sectionInsets.right
        )

        let itemCount = collectionView.numberOfSections == 0
            ? 0
            : min(collectionView.numberOfItems(inSection: 0), itemIdentifiers.count)
        if itemAttributes.count != itemCount, invalidFromIndex == nil {
            let firstChangedIndex = min(itemAttributes.count, itemCount)
            markInvalid(
                from: firstChangedIndex,
                through: max(firstChangedIndex, max(itemAttributes.count, itemCount) - 1)
            )
        }
        guard let requestedStartIndex = invalidFromIndex else {
            calculatedContentSize.width = bounds.width
            return
        }

        let previousAttributes = itemAttributes
        let previousStates = statesAfterItems
        var startIndex = min(requestedStartIndex, itemCount)
        if startIndex > previousAttributes.count || startIndex > previousStates.count {
            startIndex = 0
        }
        let invalidThrough = min(
            max(startIndex, invalidThroughIndex),
            max(startIndex, itemCount - 1)
        )

        itemAttributes = Array(previousAttributes.prefix(startIndex))
        statesAfterItems = Array(previousStates.prefix(startIndex))
        var state = startIndex == 0
            ? WaterfallLayoutCalculator.initialState(
                columnCount: columnCount,
                sectionInsets: sectionInsets
            )
            : statesAfterItems[startIndex - 1]

        var index = startIndex
        var reusedSuffixStart: Int?
        while index < itemCount {
            let identifier = itemIdentifiers[index]
            let item = WaterfallLayoutItem(
                height: measuredHeights[identifier] ?? estimatedHeight(
                    for: identifier,
                    itemWidth: currentItemWidth
                ),
                spansAllColumns: identifier == .footer
            )
            let assignedColumn: Int?
            if identifier == .footer {
                assignedColumn = nil
                columnAssignments[identifier] = nil
            } else if let existingColumn = columnAssignments[identifier],
                      state.columnBottoms.indices.contains(existingColumn)
            {
                assignedColumn = existingColumn
            } else {
                let shortestColumn = WaterfallLayoutCalculator.shortestColumnIndex(in: state)
                assignedColumn = shortestColumn
                columnAssignments[identifier] = shortestColumn
            }
            let frame = WaterfallLayoutCalculator.place(
                item: item,
                containerWidth: bounds.width,
                itemWidth: currentItemWidth,
                spacing: Self.spacing,
                sectionInsets: sectionInsets,
                columnIndex: assignedColumn,
                state: &state
            )
            let attributes = UICollectionViewLayoutAttributes(
                forCellWith: IndexPath(item: index, section: 0)
            )
            attributes.frame = frame
            itemAttributes.append(attributes)
            statesAfterItems.append(state)

            let suffixStart = index + 1
            let hasReusableSuffix =
                previousAttributes.count == itemCount
                && previousStates.count == itemCount
            let canReuseUnchangedSuffix =
                index >= invalidThrough
                && previousAttributes.indices.contains(index)
                && previousStates.indices.contains(index)
                && frame.isApproximatelyEqual(to: previousAttributes[index].frame)
                && state.isApproximatelyEqual(to: previousStates[index])
                && hasReusableSuffix
            if canReuseUnchangedSuffix {
                reusedSuffixStart = suffixStart
                if suffixStart < itemCount {
                    itemAttributes.append(contentsOf: previousAttributes[suffixStart..<itemCount])
                    statesAfterItems.append(contentsOf: previousStates[suffixStart..<itemCount])
                }
                break
            }
            index += 1
        }

        let contentHeight = itemCount == 0
            ? 0
            : (statesAfterItems.last?.columnBottoms.max() ?? 0) + sectionInsets.bottom
        calculatedContentSize = CGSize(width: bounds.width, height: contentHeight)
        updateSpatialIndex(
            replacing: startIndex..<(reusedSuffixStart ?? previousAttributes.count),
            with: startIndex..<(reusedSuffixStart ?? itemAttributes.count),
            previousAttributes: previousAttributes
        )
        invalidFromIndex = nil
        invalidThroughIndex = 0
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard !itemAttributes.isEmpty,
              let bucketRange = Self.verticalBucketRange(for: rect)
        else { return [] }

        var candidateIndexes = Set<Int>()
        for bucket in bucketRange {
            itemIndexesByVerticalBucket[bucket]?.forEach {
                candidateIndexes.insert($0)
            }
        }
        return candidateIndexes
            .sorted()
            .compactMap { index in
                guard itemAttributes.indices.contains(index),
                      itemAttributes[index].frame.intersects(rect)
                else { return nil }
                return itemAttributes[index]
            }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard indexPath.section == 0, itemAttributes.indices.contains(indexPath.item) else {
            return nil
        }
        return itemAttributes[indexPath.item]
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let collectionView else { return false }
        return abs(collectionView.bounds.width - newBounds.width) > 0.5
            || lastColumnCount != Self.columnCount(
                for: newBounds,
                collectionView: collectionView
            )
    }

    override func invalidateLayout(with context: UICollectionViewLayoutInvalidationContext) {
        if invalidFromIndex == nil,
           context.invalidateEverything || context.invalidateDataSourceCounts
        {
            markInvalid(from: 0, through: max(0, itemIdentifiers.count - 1))
        }
        super.invalidateLayout(with: context)
    }
}

private extension WaterfallCollectionLayout {
    static let spacing: CGFloat = 12

    static func isWidePad(bounds: CGRect) -> Bool {
        UIDevice.current.userInterfaceIdiom == .pad && bounds.width >= 744
    }

    static func columnCount(
        for bounds: CGRect,
        collectionView: UICollectionView
    ) -> Int {
        guard isWidePad(bounds: bounds) else { return 2 }
        let orientation = collectionView.window?
            .windowScene?
            .effectiveGeometry
            .interfaceOrientation
        let isLandscape = orientation.map {
            [.landscapeLeft, .landscapeRight].contains($0)
        } ?? false
        return isLandscape ? 5 : 4
    }

    static func sectionInsets(for bounds: CGRect) -> UIEdgeInsets {
        .init(
            top: 8,
            left: isWidePad(bounds: bounds) ? 16 : 12,
            bottom: 16,
            right: isWidePad(bounds: bounds) ? 16 : 12
        )
    }

    func estimatedHeight(for identifier: WaterfallItemID, itemWidth: CGFloat) -> CGFloat {
        switch identifier {
        case .gallery:
            let informationHeight = estimatedGalleryExtraHeightProvider?(
                identifier,
                itemWidth
            ) ?? estimatedGalleryExtraHeight
            return itemWidth / Defaults.ImageSize.rowAspect + informationHeight
        case .footer:
            return estimatedFooterHeight
        }
    }

    func markInvalid(from startIndex: Int, through endIndex: Int) {
        let normalizedStart = max(0, startIndex)
        let normalizedEnd = max(normalizedStart, endIndex)
        invalidFromIndex = min(invalidFromIndex ?? normalizedStart, normalizedStart)
        invalidThroughIndex = max(invalidThroughIndex, normalizedEnd)
    }

    func updateSpatialIndex(
        replacing previousRange: Range<Int>,
        with currentRange: Range<Int>,
        previousAttributes: [UICollectionViewLayoutAttributes]
    ) {
        let startIndex = min(previousRange.lowerBound, currentRange.lowerBound)
        let endIndex = max(previousRange.upperBound, currentRange.upperBound)
        var affectedBuckets = Set<Int>()
        for attributes in previousAttributes[previousRange] {
            guard let range = Self.verticalBucketRange(for: attributes.frame) else { continue }
            affectedBuckets.formUnion(range)
        }
        for index in currentRange {
            guard let range = Self.verticalBucketRange(
                for: itemAttributes[index].frame
            ) else { continue }
            affectedBuckets.formUnion(range)
        }
        for bucket in affectedBuckets {
            guard var indexes = itemIndexesByVerticalBucket[bucket] else { continue }
            indexes.removeAll { $0 >= startIndex && $0 < endIndex }
            itemIndexesByVerticalBucket[bucket] = indexes.isEmpty ? nil : indexes
        }

        for index in currentRange {
            guard let range = Self.verticalBucketRange(
                for: itemAttributes[index].frame
            ) else { continue }
            for bucket in range {
                itemIndexesByVerticalBucket[bucket, default: []].append(index)
            }
        }
    }

    static func verticalBucketRange(for rect: CGRect) -> ClosedRange<Int>? {
        guard rect.height > 0,
              rect.minY.isFinite,
              rect.maxY.isFinite
        else { return nil }

        let firstBucket = Int(floor(rect.minY / spatialBucketHeight))
        let lastY = max(rect.minY, rect.maxY - 0.001)
        let lastBucket = Int(floor(lastY / spatialBucketHeight))
        return firstBucket...max(firstBucket, lastBucket)
    }
}

private extension CGRect {
    func isApproximatelyEqual(to other: CGRect) -> Bool {
        abs(minX - other.minX) <= 0.25
            && abs(minY - other.minY) <= 0.25
            && abs(width - other.width) <= 0.25
            && abs(height - other.height) <= 0.25
    }
}
