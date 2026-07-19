//
//  AdvancedList.swift
//  EhPanda
//

import SwiftUI
import Kingfisher
import VisionKit

enum ReadingScrollAxis: Equatable {
    case vertical
    case horizontal
}

enum ReadingPageIndexMapper {
    static func clamped(_ index: Int, itemCount: Int) -> Int {
        min(max(index, 0), max(itemCount - 1, 0))
    }

    static func displayIndex(
        forLogicalIndex index: Int,
        itemCount: Int,
        isReversed: Bool
    ) -> Int {
        isReversed ? itemCount - 1 - index : index
    }

    static func logicalIndex(
        forDisplayIndex index: Int,
        itemCount: Int,
        isReversed: Bool
    ) -> Int {
        isReversed ? itemCount - 1 - index : index
    }
}

struct ReadingImageLoadRequestGate {
    private(set) var activeRequestID: UUID?

    mutating func begin() -> UUID {
        let requestID = UUID()
        activeRequestID = requestID
        return requestID
    }

    mutating func cancel() {
        activeRequestID = nil
    }

    mutating func complete(_ requestID: UUID) -> Bool {
        guard activeRequestID == requestID else { return false }
        activeRequestID = nil
        return true
    }
}

struct ReadingCollectionView: UIViewRepresentable {
    @Binding var pageIndex: Int

    let pages: [Int]
    let axis: ReadingScrollAxis
    let isRightToLeft: Bool
    let spacing: CGFloat
    let topInset: CGFloat
    let isDualPage: Bool
    let isDatabaseLoading: Bool
    let isScrollEnabled: Bool
    let reloadID: UUID
    let backgroundColor: UIColor
    let pageModel: (Int) -> ReadingPageModel

    let fetchAction: (Int) -> Void
    let refetchAction: (Int) -> Void
    let prefetchAction: (Int) -> Void
    let retryAction: (Int) -> Void
    let loadSucceededAction: (Int) -> Void
    let loadFailedAction: (Int, URL?) -> Void
    let copyImageAction: (URL) -> Void
    let saveImageAction: (URL) -> Void
    let shareImageAction: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = .zero

        let collectionView = ReaderUICollectionView(
            frame: .zero,
            collectionViewLayout: layout
        )
        collectionView.backgroundColor = backgroundColor
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.alwaysBounceHorizontal = false
        collectionView.alwaysBounceVertical = false
        collectionView.delaysContentTouches = false
        collectionView.canCancelContentTouches = true
        collectionView.register(
            ReadingPageCell.self,
            forCellWithReuseIdentifier: ReadingPageCell.reuseIdentifier
        )

        context.coordinator.connect(to: collectionView)
        return collectionView
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
        context.coordinator.update(parent: self, collectionView: collectionView)
    }

    static func dismantleUIView(
        _ collectionView: UICollectionView,
        coordinator: Coordinator
    ) {
        coordinator.disconnect(from: collectionView)
    }
}

extension ReadingCollectionView {
    final class Coordinator: NSObject {
        private var parent: ReadingCollectionView
        private weak var collectionView: UICollectionView?
        private var imageAspectRatios = [Int: CGFloat]()
        private var pendingLayoutInvalidation = false
        private var lastBoundsSize = CGSize.zero
        private var lastPageIndex: Int
        private var isConnected = false

        init(parent: ReadingCollectionView) {
            self.parent = parent
            lastPageIndex = parent.pageIndex
        }

        func connect(to collectionView: UICollectionView) {
            self.collectionView = collectionView
            collectionView.dataSource = self
            collectionView.delegate = self
            collectionView.prefetchDataSource = self
            if let collectionView = collectionView as? ReaderUICollectionView {
                collectionView.onBoundsSizeChange = { [weak self] size in
                    self?.boundsSizeDidChange(size)
                }
            }
            isConnected = true
            applyConfiguration(to: collectionView)
            collectionView.reloadData()
            scheduleScrollToCurrentPage(animated: false)
        }

        func disconnect(from collectionView: UICollectionView) {
            collectionView.visibleCells
                .compactMap { $0 as? ReadingPageCell }
                .forEach { $0.cancelImageLoading() }
            collectionView.dataSource = nil
            collectionView.delegate = nil
            collectionView.prefetchDataSource = nil
            if let collectionView = collectionView as? ReaderUICollectionView {
                collectionView.onBoundsSizeChange = nil
            }
            self.collectionView = nil
            isConnected = false
        }

        func update(
            parent newParent: ReadingCollectionView,
            collectionView: UICollectionView
        ) {
            let oldParent = parent
            parent = newParent
            let pageIndexChanged = lastPageIndex != newParent.pageIndex
            lastPageIndex = newParent.pageIndex

            let dataChanged = oldParent.pages != newParent.pages
            let layoutChanged =
                oldParent.axis != newParent.axis
                || oldParent.isRightToLeft != newParent.isRightToLeft
                || oldParent.spacing != newParent.spacing
                || oldParent.topInset != newParent.topInset
                || oldParent.isDualPage != newParent.isDualPage
            let needsReload =
                dataChanged
                || layoutChanged
                || oldParent.reloadID != newParent.reloadID

            applyConfiguration(to: collectionView)

            if needsReload {
                if oldParent.reloadID != newParent.reloadID {
                    collectionView.visibleCells
                        .compactMap { $0 as? ReadingPageCell }
                        .forEach { $0.resetImages() }
                }
                collectionView.reloadData()
                collectionView.collectionViewLayout.invalidateLayout()
                scheduleScrollToCurrentPage(animated: false)
            } else {
                reconfigureVisibleCells(in: collectionView)
                if oldParent.isDatabaseLoading,
                   !newParent.isDatabaseLoading
                {
                    collectionView.indexPathsForVisibleItems.forEach {
                        loadPageIfNeeded(at: $0)
                    }
                }
                if pageIndexChanged,
                   !isUserInteracting(with: collectionView)
                {
                    scrollToCurrentPage(animated: true)
                }
            }
        }

        private func applyConfiguration(to collectionView: UICollectionView) {
            guard let layout = collectionView.collectionViewLayout
                as? UICollectionViewFlowLayout
            else { return }

            let isHorizontal = parent.axis == .horizontal
            layout.scrollDirection = isHorizontal ? .horizontal : .vertical
            layout.minimumLineSpacing = isHorizontal ? 0 : parent.spacing

            collectionView.isPagingEnabled = isHorizontal
            collectionView.decelerationRate = isHorizontal ? .fast : .normal
            collectionView.alwaysBounceHorizontal = isHorizontal
            collectionView.alwaysBounceVertical = !isHorizontal
            collectionView.isScrollEnabled = parent.isScrollEnabled
            collectionView.backgroundColor = parent.backgroundColor

            let topInset = isHorizontal ? 0 : parent.topInset
            let inset = UIEdgeInsets(
                top: topInset,
                left: 0,
                bottom: 0,
                right: 0
            )
            if collectionView.contentInset != inset {
                collectionView.contentInset = inset
                collectionView.verticalScrollIndicatorInsets = inset
            }
        }

        private func boundsSizeDidChange(_ size: CGSize) {
            guard isConnected, size != lastBoundsSize else { return }
            lastBoundsSize = size
            collectionView?.collectionViewLayout.invalidateLayout()
            collectionView?.visibleCells
                .compactMap { $0 as? ReadingPageCell }
                .forEach { $0.resetImages() }
            reconfigureVisibleCells()
            scheduleScrollToCurrentPage(animated: false)
        }

        private func scheduleScrollToCurrentPage(animated: Bool) {
            DispatchQueue.main.async { [weak self] in
                self?.scrollToCurrentPage(animated: animated)
            }
        }

        private func scrollToCurrentPage(animated: Bool) {
            guard let collectionView, !parent.pages.isEmpty else { return }
            let logicalIndex = clampedPageIndex(parent.pageIndex)
            let displayIndex = displayIndex(forLogicalIndex: logicalIndex)
            guard displayIndex >= 0,
                  displayIndex < collectionView.numberOfItems(inSection: 0)
            else { return }

            let position: UICollectionView.ScrollPosition =
                parent.axis == .horizontal
                ? .centeredHorizontally
                : .top
            collectionView.scrollToItem(
                at: IndexPath(item: displayIndex, section: 0),
                at: position,
                animated: animated
            )
        }

        private func reconfigureVisibleCells(
            in collectionView: UICollectionView? = nil
        ) {
            guard let collectionView = collectionView ?? self.collectionView else {
                return
            }
            for indexPath in collectionView.indexPathsForVisibleItems {
                guard let cell = collectionView.cellForItem(at: indexPath)
                    as? ReadingPageCell
                else { continue }
                configure(cell: cell, at: indexPath, in: collectionView)
            }
        }

        private func configure(
            cell: ReadingPageCell,
            at indexPath: IndexPath,
            in collectionView: UICollectionView
        ) {
            guard let page = page(atDisplayIndex: indexPath.item) else {
                cell.resetImages()
                return
            }
            let model = parent.pageModel(page)
            let pointWidth = collectionView.bounds.width
                / (parent.isDualPage ? 2 : 1)
            let displayScale = max(collectionView.traitCollection.displayScale, 1)
            let targetPixelSize = CGSize(
                width: max(pointWidth * displayScale, 1),
                height: max(
                    pointWidth / Defaults.ImageSize.contentAspect * displayScale,
                    1
                )
            )

            cell.configure(
                model: model,
                isDualPage: parent.isDualPage,
                backgroundColor: parent.backgroundColor,
                targetPixelSize: targetPixelSize,
                retryAction: parent.retryAction,
                loadSucceededAction: parent.loadSucceededAction,
                loadFailedAction: parent.loadFailedAction,
                imageAspectChangedAction: { [weak self] index, aspectRatio in
                    self?.imageAspectRatioDidChange(
                        index: index,
                        aspectRatio: aspectRatio
                    )
                }
            )
        }

        private func loadPageIfNeeded(at indexPath: IndexPath) {
            guard !parent.isDatabaseLoading,
                  let page = page(atDisplayIndex: indexPath.item)
            else { return }
            let model = parent.pageModel(page)
            for image in model.images where image.imageURL == nil {
                parent.fetchAction(image.index)
            }
            parent.prefetchAction(page)
        }

        private func imageAspectRatioDidChange(
            index: Int,
            aspectRatio: CGFloat
        ) {
            guard parent.axis == .vertical,
                  aspectRatio.isFinite,
                  aspectRatio > 0,
                  abs((imageAspectRatios[index] ?? 0) - aspectRatio) > 0.001
            else { return }

            imageAspectRatios[index] = aspectRatio
            if let collectionView, isUserInteracting(with: collectionView) {
                pendingLayoutInvalidation = true
            } else {
                applyPendingLayoutInvalidation(force: true)
            }
        }

        private func applyPendingLayoutInvalidation(force: Bool = false) {
            guard force || pendingLayoutInvalidation,
                  let collectionView
            else { return }
            pendingLayoutInvalidation = false

            let anchor = captureVerticalAnchor(in: collectionView)
            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.layoutIfNeeded()
            restoreVerticalAnchor(anchor, in: collectionView)
        }

        private func captureVerticalAnchor(
            in collectionView: UICollectionView
        ) -> (IndexPath, CGFloat)? {
            guard parent.axis == .vertical else { return nil }
            let visible = collectionView.indexPathsForVisibleItems.sorted()
            guard let indexPath = visible.first,
                  let attributes = collectionView.layoutAttributesForItem(
                    at: indexPath
                  )
            else { return nil }
            return (
                indexPath,
                collectionView.contentOffset.y - attributes.frame.minY
            )
        }

        private func restoreVerticalAnchor(
            _ anchor: (IndexPath, CGFloat)?,
            in collectionView: UICollectionView
        ) {
            guard let anchor,
                  let attributes = collectionView.layoutAttributesForItem(
                    at: anchor.0
                  )
            else { return }
            collectionView.contentOffset.y = attributes.frame.minY + anchor.1
        }

        private func reportCurrentPage() {
            guard let collectionView, !parent.pages.isEmpty else { return }
            let center = CGPoint(
                x: collectionView.contentOffset.x
                    + collectionView.bounds.width / 2,
                y: collectionView.contentOffset.y
                    + collectionView.bounds.height / 2
            )
            guard let indexPath = collectionView.indexPathForItem(at: center)
                ?? nearestVisibleIndexPath(in: collectionView)
            else { return }

            let logicalIndex = logicalIndex(forDisplayIndex: indexPath.item)
            if parent.pageIndex != logicalIndex {
                lastPageIndex = logicalIndex
                parent.pageIndex = logicalIndex
            }
        }

        private func nearestVisibleIndexPath(
            in collectionView: UICollectionView
        ) -> IndexPath? {
            collectionView.indexPathsForVisibleItems.min { lhs, rhs in
                guard let lhsFrame = collectionView.layoutAttributesForItem(
                    at: lhs
                )?.frame,
                let rhsFrame = collectionView.layoutAttributesForItem(
                    at: rhs
                )?.frame
                else { return lhs.item < rhs.item }

                let viewportCenter = parent.axis == .horizontal
                    ? collectionView.contentOffset.x
                        + collectionView.bounds.width / 2
                    : collectionView.contentOffset.y
                        + collectionView.bounds.height / 2
                let lhsDistance = parent.axis == .horizontal
                    ? abs(lhsFrame.midX - viewportCenter)
                    : abs(lhsFrame.midY - viewportCenter)
                let rhsDistance = parent.axis == .horizontal
                    ? abs(rhsFrame.midX - viewportCenter)
                    : abs(rhsFrame.midY - viewportCenter)
                return lhsDistance < rhsDistance
            }
        }

        private func isUserInteracting(
            with collectionView: UICollectionView
        ) -> Bool {
            collectionView.isTracking
                || collectionView.isDragging
                || collectionView.isDecelerating
        }

        private func clampedPageIndex(_ index: Int) -> Int {
            ReadingPageIndexMapper.clamped(
                index,
                itemCount: parent.pages.count
            )
        }

        private func displayIndex(forLogicalIndex index: Int) -> Int {
            ReadingPageIndexMapper.displayIndex(
                forLogicalIndex: index,
                itemCount: parent.pages.count,
                isReversed: isReversed
            )
        }

        private func logicalIndex(forDisplayIndex index: Int) -> Int {
            ReadingPageIndexMapper.logicalIndex(
                forDisplayIndex: index,
                itemCount: parent.pages.count,
                isReversed: isReversed
            )
        }

        private var isReversed: Bool {
            parent.axis == .horizontal && parent.isRightToLeft
        }

        private func page(atDisplayIndex index: Int) -> Int? {
            let logicalIndex = logicalIndex(forDisplayIndex: index)
            guard parent.pages.indices.contains(logicalIndex) else {
                return nil
            }
            return parent.pages[logicalIndex]
        }
    }
}

extension ReadingCollectionView.Coordinator:
    UICollectionViewDataSource,
    UICollectionViewDelegateFlowLayout,
    UICollectionViewDataSourcePrefetching
{
    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        parent.pages.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ReadingPageCell.reuseIdentifier,
            for: indexPath
        )
        guard let cell = cell as? ReadingPageCell else { return cell }
        configure(cell: cell, at: indexPath, in: collectionView)
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let width = max(collectionView.bounds.width, 1)
        guard parent.axis == .vertical,
              let imageIndex = page(atDisplayIndex: indexPath.item)
        else {
            return CGSize(
                width: width,
                height: max(collectionView.bounds.height, 1)
            )
        }

        let aspectRatio = imageAspectRatios[imageIndex]
            ?? Defaults.ImageSize.contentAspect
        return CGSize(
            width: width,
            height: max(width / aspectRatio, 1)
        )
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        guard let cell = cell as? ReadingPageCell else { return }
        configure(cell: cell, at: indexPath, in: collectionView)
        DispatchQueue.main.async { [weak self] in
            self?.loadPageIfNeeded(at: indexPath)
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didEndDisplaying cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        (cell as? ReadingPageCell)?.cancelImageLoading()
    }

    func collectionView(
        _ collectionView: UICollectionView,
        prefetchItemsAt indexPaths: [IndexPath]
    ) {
        let uniquePaths = Dictionary(
            grouping: indexPaths,
            by: \.item
        ).compactMap { $0.value.first }
        DispatchQueue.main.async { [weak self] in
            uniquePaths.forEach { self?.loadPageIfNeeded(at: $0) }
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        applyPendingLayoutInvalidation()
        reportCurrentPage()
    }

    func scrollViewDidEndDragging(
        _ scrollView: UIScrollView,
        willDecelerate decelerate: Bool
    ) {
        if !decelerate {
            applyPendingLayoutInvalidation()
            reportCurrentPage()
        }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        applyPendingLayoutInvalidation()
        reportCurrentPage()
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let cell = collectionView.cellForItem(at: indexPath)
            as? ReadingPageCell
        else { return nil }

        let pointInCell = collectionView.convert(point, to: cell)
        guard let model = cell.imageModel(at: pointInCell),
              !model.enablesLiveText
        else { return nil }

        return UIContextMenuConfiguration(
            identifier: nil,
            previewProvider: nil
        ) { [weak self] _ in
            guard let self else { return nil }
            let actions = contextMenuActions(for: model)
            return actions.isEmpty ? nil : UIMenu(children: actions)
        }
    }

    private func contextMenuActions(
        for model: ReadingImageModel
    ) -> [UIMenuElement] {
        var actions = [UIMenuElement]()

        if model.imageURL?.isFileURL != true {
            actions.append(
                UIAction(
                    title: L10n.Localizable.ReadingView.ContextMenu.Button.reload,
                    image: UIImage(systemName: "arrow.counterclockwise")
                ) { [weak self] _ in
                    guard let self else { return }
                    if model.imageURL == nil {
                        parent.retryAction(model.index)
                    } else {
                        parent.refetchAction(model.index)
                    }
                }
            )
        }

        if let imageURL = model.imageURL {
            actions.append(
                UIAction(
                    title: L10n.Localizable.ReadingView.ContextMenu.Button.copy,
                    image: UIImage(systemName: "plus.square.on.square")
                ) { [weak self] _ in
                    self?.parent.copyImageAction(imageURL)
                }
            )
            actions.append(
                UIAction(
                    title: L10n.Localizable.ReadingView.ContextMenu.Button.save,
                    image: UIImage(systemName: "square.and.arrow.down")
                ) { [weak self] _ in
                    self?.parent.saveImageAction(imageURL)
                }
            )
            if let originalImageURL = model.originalImageURL {
                actions.append(
                    UIAction(
                        title: L10n.Localizable.ReadingView.ContextMenu.Button.saveOriginal,
                        image: UIImage(
                            systemName: "square.and.arrow.down.on.square"
                        )
                    ) { [weak self] _ in
                        self?.parent.saveImageAction(originalImageURL)
                    }
                )
            }
            actions.append(
                UIAction(
                    title: L10n.Localizable.ReadingView.ContextMenu.Button.share,
                    image: UIImage(systemName: "square.and.arrow.up")
                ) { [weak self] _ in
                    self?.parent.shareImageAction(imageURL)
                }
            )
        }

        return actions
    }
}

private final class ReaderUICollectionView: UICollectionView {
    var onBoundsSizeChange: ((CGSize) -> Void)?
    private var previousBoundsSize = CGSize.zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != previousBoundsSize else { return }
        previousBoundsSize = bounds.size
        onBoundsSizeChange?(bounds.size)
    }
}

private final class ReadingPageCell: UICollectionViewCell {
    static let reuseIdentifier = "ReadingPageCell"

    private let firstSlot = ReadingImageSlotView()
    private let secondSlot = ReadingImageSlotView()
    private var model: ReadingPageModel?
    private var isDualPage = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(firstSlot)
        contentView.addSubview(secondSlot)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        model = nil
        firstSlot.reset()
        secondSlot.reset()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        if isDualPage {
            let slotWidth = contentView.bounds.width / 2
            if model?.second != nil {
                firstSlot.frame = CGRect(
                    x: 0,
                    y: 0,
                    width: slotWidth,
                    height: contentView.bounds.height
                )
                secondSlot.frame = CGRect(
                    x: slotWidth,
                    y: 0,
                    width: slotWidth,
                    height: contentView.bounds.height
                )
            } else {
                firstSlot.frame = CGRect(
                    x: (contentView.bounds.width - slotWidth) / 2,
                    y: 0,
                    width: slotWidth,
                    height: contentView.bounds.height
                )
                secondSlot.frame = .zero
            }
        } else {
            firstSlot.frame = contentView.bounds
            secondSlot.frame = .zero
        }
    }

    func configure(
        model: ReadingPageModel,
        isDualPage: Bool,
        backgroundColor: UIColor,
        targetPixelSize: CGSize,
        retryAction: @escaping (Int) -> Void,
        loadSucceededAction: @escaping (Int) -> Void,
        loadFailedAction: @escaping (Int, URL?) -> Void,
        imageAspectChangedAction: @escaping (Int, CGFloat) -> Void
    ) {
        self.model = model
        self.isDualPage = isDualPage
        contentView.backgroundColor = backgroundColor

        if let first = model.first {
            firstSlot.configure(
                model: first,
                backgroundColor: backgroundColor,
                targetPixelSize: targetPixelSize,
                retryAction: retryAction,
                loadSucceededAction: loadSucceededAction,
                loadFailedAction: loadFailedAction,
                imageAspectChangedAction: imageAspectChangedAction
            )
        } else {
            firstSlot.reset()
        }

        if let second = model.second {
            secondSlot.configure(
                model: second,
                backgroundColor: backgroundColor,
                targetPixelSize: targetPixelSize,
                retryAction: retryAction,
                loadSucceededAction: loadSucceededAction,
                loadFailedAction: loadFailedAction,
                imageAspectChangedAction: imageAspectChangedAction
            )
        } else {
            secondSlot.reset()
        }

        setNeedsLayout()
    }

    func imageModel(at point: CGPoint) -> ReadingImageModel? {
        guard let model else { return nil }
        if model.second != nil, secondSlot.frame.contains(point) {
            return model.second
        }
        return model.first
    }

    func cancelImageLoading() {
        firstSlot.cancelImageLoading()
        secondSlot.cancelImageLoading()
    }

    func resetImages() {
        firstSlot.resetImage()
        secondSlot.resetImage()
    }
}

private final class ReadingImageSlotView: UIView {
    private let imageView = AnimatedImageView()
    private let placeholderView = UIView()
    private let pageLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let retryButton = UIButton(type: .system)

    private let imageAnalyzer = ImageAnalyzer()
    private let imageAnalysisInteraction = ImageAnalysisInteraction()
    private var imageAnalysisTask: Task<Void, Never>?
    private var analyzedURL: URL?
    private var representedURL: URL?
    private var imageLoadRequestGate = ReadingImageLoadRequestGate()
    private var model: ReadingImageModel?
    private var targetPixelSize = CGSize.zero
    private var retryHandler: (() -> Void)?
    private var loadSucceededHandler: (() -> Void)?
    private var loadFailedHandler: ((URL?) -> Void)?
    private var imageAspectChangedHandler: ((CGFloat) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        clipsToBounds = true
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = true
        imageAnalysisInteraction.preferredInteractionTypes = .automaticTextOnly
        imageView.addInteraction(imageAnalysisInteraction)

        pageLabel.textAlignment = .center
        pageLabel.textColor = .gray
        pageLabel.font = .preferredFont(forTextStyle: .largeTitle)
        pageLabel.adjustsFontForContentSizeCategory = true
        pageLabel.adjustsFontSizeToFitWidth = true
        pageLabel.minimumScaleFactor = 0.5
        pageLabel.numberOfLines = 1

        progressView.progress = 0
        progressView.trackTintColor = UIColor.gray.withAlphaComponent(0.25)

        retryButton.setImage(
            UIImage(systemName: "arrow.clockwise.circle"),
            for: .normal
        )
        retryButton.tintColor = .gray
        retryButton.addTarget(
            self,
            action: #selector(retryButtonTapped),
            for: .touchUpInside
        )

        addSubview(imageView)
        addSubview(placeholderView)
        placeholderView.addSubview(pageLabel)
        placeholderView.addSubview(progressView)
        placeholderView.addSubview(activityIndicator)
        placeholderView.addSubview(retryButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        placeholderView.frame = bounds

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        pageLabel.frame = CGRect(
            x: 16,
            y: center.y - 72,
            width: max(bounds.width - 32, 0),
            height: 48
        )

        let progressWidth = min(bounds.width * 0.5, 240)
        progressView.frame = CGRect(
            x: center.x - progressWidth / 2,
            y: center.y + 24,
            width: progressWidth,
            height: 4
        )

        activityIndicator.center = CGPoint(x: center.x, y: center.y + 24)
        retryButton.frame = CGRect(
            x: center.x - 24,
            y: center.y,
            width: 48,
            height: 48
        )
    }

    func configure(
        model: ReadingImageModel,
        backgroundColor: UIColor,
        targetPixelSize: CGSize,
        retryAction: @escaping (Int) -> Void,
        loadSucceededAction: @escaping (Int) -> Void,
        loadFailedAction: @escaping (Int, URL?) -> Void,
        imageAspectChangedAction: @escaping (Int, CGFloat) -> Void
    ) {
        let previousModel = self.model
        let sizeChanged = self.targetPixelSize != targetPixelSize
        let backgroundChanged = self.backgroundColor != backgroundColor
        let liveTextChanged =
            previousModel?.enablesLiveText != model.enablesLiveText
            || previousModel?.imageURL != model.imageURL

        self.model = model
        self.targetPixelSize = targetPixelSize
        self.backgroundColor = backgroundColor
        placeholderView.backgroundColor = backgroundColor
        pageLabel.text = String(model.index)
        retryHandler = { retryAction(model.index) }
        loadSucceededHandler = { loadSucceededAction(model.index) }
        loadFailedHandler = { loadFailedAction(model.index, $0) }
        imageAspectChangedHandler = {
            imageAspectChangedAction(model.index, $0)
        }

        if liveTextChanged {
            updateLiveTextAnalysis()
        }

        let needsImageLoad =
            model.loadingState == .idle
            && model.imageURL != nil
            && (
                representedURL != model.imageURL
                || imageView.image == nil
            )
        guard previousModel != model
                || sizeChanged
                || backgroundChanged
                || needsImageLoad
        else {
            return
        }

        switch model.loadingState {
        case .failed:
            showFailure()

        case .loading:
            if previousModel?.loadingState != .loading {
                resetImage()
            }
            showLoading(usesProgress: false)

        case .idle:
            guard let imageURL = model.imageURL else {
                showLoading(usesProgress: false)
                return
            }
            if representedURL == imageURL,
               imageView.image != nil,
               !sizeChanged
            {
                showImage()
            } else {
                loadImage(from: imageURL)
            }
        }
    }

    func cancelImageLoading() {
        imageLoadRequestGate.cancel()
        imageView.kf.cancelDownloadTask()
    }

    func resetImage() {
        cancelImageLoading()
        clearLiveTextAnalysis()
        representedURL = nil
        imageView.image = nil
    }

    func reset() {
        resetImage()
        model = nil
        retryHandler = nil
        loadSucceededHandler = nil
        loadFailedHandler = nil
        imageAspectChangedHandler = nil
        clearLiveTextAnalysis()
        placeholderView.isHidden = true
        imageView.isHidden = true
        progressView.isHidden = true
        retryButton.isHidden = true
        activityIndicator.stopAnimating()
        activityIndicator.isHidden = true
    }

    @objc private func retryButtonTapped() {
        retryHandler?()
    }

    private func loadImage(from imageURL: URL) {
        cancelImageLoading()
        representedURL = imageURL
        imageView.image = nil
        showLoading(usesProgress: true)
        let requestID = imageLoadRequestGate.begin()

        var options: KingfisherOptionsInfo = [
            .backgroundDecode
        ]
        if imageURL.isFileURL {
            options.append(.cacheMemoryOnly)
        } else {
            options.append(.cacheOriginalImage)
        }
        if !imageURL.isGIF {
            options.append(
                .processor(
                    DownsamplingImageProcessor(size: targetPixelSize)
                )
            )
        }

        imageView.kf.setImage(
            with: imageURL,
            options: options,
            progressBlock: { [weak self] received, total in
                guard total > 0 else { return }
                self?.progressView.progress = Float(received) / Float(total)
            },
            completionHandler: { [weak self] result in
                guard let self,
                      representedURL == imageURL,
                      imageLoadRequestGate.complete(requestID)
                else { return }
                switch result {
                case .success(let value):
                    showImage()
                    updateLiveTextAnalysis(force: true)
                    let size = value.image.size
                    if size.width > 0, size.height > 0 {
                        imageAspectChangedHandler?(size.width / size.height)
                    }
                    loadSucceededHandler?()

                case .failure:
                    showFailure()
                    loadFailedHandler?(imageURL)
                }
            }
        )
    }

    private func showImage() {
        placeholderView.isHidden = true
        imageView.isHidden = false
        activityIndicator.stopAnimating()
        setNeedsLayout()
    }

    private func showLoading(usesProgress: Bool) {
        placeholderView.isHidden = false
        imageView.isHidden = true
        retryButton.isHidden = true
        progressView.isHidden = !usesProgress
        progressView.progress = 0
        activityIndicator.isHidden = usesProgress
        if usesProgress {
            activityIndicator.stopAnimating()
        } else {
            activityIndicator.startAnimating()
        }
    }

    private func showFailure() {
        placeholderView.isHidden = false
        imageView.isHidden = true
        progressView.isHidden = true
        activityIndicator.stopAnimating()
        activityIndicator.isHidden = true
        retryButton.isHidden = false
    }

    private func updateLiveTextAnalysis(force: Bool = false) {
        guard let model,
              model.enablesLiveText,
              ImageAnalyzer.isSupported,
              let image = imageView.image,
              let imageURL = model.imageURL,
              representedURL == imageURL
        else {
            clearLiveTextAnalysis()
            return
        }

        guard force || analyzedURL != imageURL else { return }

        imageAnalysisTask?.cancel()
        imageAnalysisInteraction.analysis = nil
        imageAnalysisInteraction.selectableItemsHighlighted = false
        analyzedURL = imageURL

        imageAnalysisTask = Task { [weak self] in
            do {
                let configuration = ImageAnalyzer.Configuration([.text])
                let analysis = try await self?.imageAnalyzer.analyze(
                    image,
                    configuration: configuration
                )
                guard !Task.isCancelled,
                      let self,
                      self.model?.enablesLiveText == true,
                      self.model?.imageURL == imageURL
                else { return }
                imageAnalysisInteraction.analysis = analysis
                imageAnalysisInteraction.selectableItemsHighlighted =
                    analysis?.hasResults(for: .text) == true
                imageAnalysisTask = nil
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                Logger.info(
                    "Live Text analysis failed",
                    context: ["index": model.index, "error": error]
                )
            }
        }
    }

    private func clearLiveTextAnalysis() {
        imageAnalysisTask?.cancel()
        imageAnalysisTask = nil
        analyzedURL = nil
        imageAnalysisInteraction.resetTextSelection()
        imageAnalysisInteraction.selectableItemsHighlighted = false
        imageAnalysisInteraction.analysis = nil
    }
}
