//
//  GenericList.swift
//  EhPanda
//

import SwiftUI
import ComposableArchitecture

struct GenericList: View {
    private let galleries: [Gallery]
    private let setting: Setting
    private let translationRevision: TagTranslator.RenderRevision?
    private let datasetIdentity: AnyHashable
    private let presentations: [String: GalleryListPresentation]
    private let actionsProvider: ((String) -> [GalleryListAction])?
    private let pageNumber: PageNumber?
    private let loadingState: LoadingState
    private let footerLoadingState: LoadingState
    private let fetchAction: (() -> Void)?
    private let fetchMoreAction: (() -> Void)?
    private let navigateAction: ((String) -> Void)?
    private let translateAction: ((String) -> (String, TagTranslation?))?

    init(
        galleries: [Gallery], setting: Setting,
        translationRevision: TagTranslator.RenderRevision? = nil,
        datasetIdentity: AnyHashable = AnyHashable(0),
        presentations: [String: GalleryListPresentation] = [:],
        actionsProvider: ((String) -> [GalleryListAction])? = nil,
        pageNumber: PageNumber?,
        loadingState: LoadingState, footerLoadingState: LoadingState,
        fetchAction: (() -> Void)? = nil,
        fetchMoreAction: (() -> Void)? = nil,
        navigateAction: ((String) -> Void)? = nil,
        translateAction: ((String) -> (String, TagTranslation?))? = nil
    ) {
        self.galleries = galleries
        self.setting = setting
        self.translationRevision = translationRevision
        self.datasetIdentity = datasetIdentity
        self.presentations = presentations
        self.actionsProvider = actionsProvider
        self.pageNumber = pageNumber
        self.loadingState = loadingState
        self.footerLoadingState = footerLoadingState
        self.fetchAction = fetchAction
        self.fetchMoreAction = fetchMoreAction
        self.navigateAction = navigateAction
        self.translateAction = translateAction
    }

    var body: some View {
        Group {
            switch setting.listDisplayMode {
            case .detail:
                DetailList(
                    galleries: galleries, setting: setting, pageNumber: pageNumber,
                    presentations: presentations,
                    actionsProvider: actionsProvider,
                    footerLoadingState: footerLoadingState, fetchMoreAction: fetchMoreAction,
                    navigateAction: navigateAction, translateAction: translateAction
                )
                .refreshable { fetchAction?() }
            case .waterfall:
                WaterfallList(
                    galleries: galleries, setting: setting,
                    translationRevision: translationRevision,
                    datasetIdentity: datasetIdentity, pageNumber: pageNumber,
                    presentations: presentations,
                    actionsProvider: actionsProvider,
                    loadingState: loadingState, footerLoadingState: footerLoadingState,
                    fetchAction: fetchAction, fetchMoreAction: fetchMoreAction,
                    navigateAction: navigateAction, translateAction: translateAction
                )
            }
        }
        .opacity(loadingState == .idle ? 1 : 0)
        .overlay {
            if loadingState == .loading {
                LoadingView()
            } else if let error = loadingState.failed {
                ErrorView(error: error, action: fetchAction)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: loadingState)
    }
}

// MARK: DetailList
private struct DetailList: View {
    private let galleries: [Gallery]
    private let setting: Setting
    private let pageNumber: PageNumber?
    private let presentations: [String: GalleryListPresentation]
    private let actionsProvider: ((String) -> [GalleryListAction])?
    private let footerLoadingState: LoadingState
    private let fetchMoreAction: (() -> Void)?
    private let navigateAction: ((String) -> Void)?
    private let translateAction: ((String) -> (String, TagTranslation?))?

    init(
        galleries: [Gallery], setting: Setting, pageNumber: PageNumber?,
        presentations: [String: GalleryListPresentation],
        actionsProvider: ((String) -> [GalleryListAction])?,
        footerLoadingState: LoadingState,
        fetchMoreAction: (() -> Void)?,
        navigateAction: ((String) -> Void)? = nil,
        translateAction: ((String) -> (String, TagTranslation?))? = nil
    ) {
        self.galleries = galleries
        self.setting = setting
        self.pageNumber = pageNumber
        self.presentations = presentations
        self.actionsProvider = actionsProvider
        self.footerLoadingState = footerLoadingState
        self.fetchMoreAction = fetchMoreAction
        self.navigateAction = navigateAction
        self.translateAction = translateAction
    }

    private func shouldShowFooter(gallery: Gallery) -> Bool {
        guard let pageNumber = pageNumber else { return false }

        let isLastGallery = gallery == galleries.last
        let isPageNumberValid = pageNumber.hasNextPage()
        let isLoadingStateIdle = footerLoadingState == .idle

        return isLastGallery && isPageNumberValid && !isLoadingStateIdle
    }

    var body: some View {
        List {
            ForEach(galleries) { gallery in
                let actions = actionsProvider?(gallery.id) ?? []

                GalleryDetailCell(
                    gallery: gallery,
                    setting: setting,
                    presentation: presentations[gallery.id],
                    actions: actions,
                    translateAction: translateAction
                )
                .contentShape(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .onTapGesture {
                    navigateAction?(gallery.id)
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    navigateAction?(gallery.id)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    swipeButtons(
                        actions.filter { $0.edge == .leading }
                    )
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    swipeButtons(
                        actions.filter { $0.edge == .trailing }
                    )
                }
                .listRowInsets(
                    .init(top: 6, leading: 16, bottom: 6, trailing: 16)
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .onAppear {
                    if gallery == galleries.last,
                       pageNumber?.hasNextPage() == true,
                       footerLoadingState == .idle
                    {
                        fetchMoreAction?()
                    }
                }

                if shouldShowFooter(gallery: gallery) {
                    FetchMoreFooter(
                        loadingState: footerLoadingState,
                        retryAction: fetchMoreAction
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .ignoresSafeArea(.container, edges: .bottom)
    }

    @ViewBuilder
    private func swipeButtons(_ actions: [GalleryListAction]) -> some View {
        ForEach(actions.indices, id: \.self) { index in
            let item = actions[index]
            Button(role: item.role.buttonRole, action: item.action) {
                Label(item.title, systemImage: item.systemImage)
            }
            .tint(item.tint.color)
        }
    }
}

// MARK: WaterfallList
private struct WaterfallList: View {
    private let galleries: [Gallery]
    private let setting: Setting
    private let translationRevision: TagTranslator.RenderRevision?
    private let datasetIdentity: AnyHashable
    private let pageNumber: PageNumber?
    private let presentations: [String: GalleryListPresentation]
    private let actionsProvider: ((String) -> [GalleryListAction])?
    private let loadingState: LoadingState
    private let footerLoadingState: LoadingState
    private let fetchAction: (() -> Void)?
    private let fetchMoreAction: (() -> Void)?
    private let navigateAction: ((String) -> Void)?
    private let translateAction: ((String) -> (String, TagTranslation?))?

    init(
        galleries: [Gallery], setting: Setting,
        translationRevision: TagTranslator.RenderRevision?,
        datasetIdentity: AnyHashable,
        pageNumber: PageNumber?,
        presentations: [String: GalleryListPresentation],
        actionsProvider: ((String) -> [GalleryListAction])?,
        loadingState: LoadingState, footerLoadingState: LoadingState,
        fetchAction: (() -> Void)?,
        fetchMoreAction: (() -> Void)?,
        navigateAction: ((String) -> Void)? = nil,
        translateAction: ((String) -> (String, TagTranslation?))? = nil
    ) {
        self.galleries = galleries
        self.setting = setting
        self.translationRevision = translationRevision
        self.datasetIdentity = datasetIdentity
        self.pageNumber = pageNumber
        self.presentations = presentations
        self.actionsProvider = actionsProvider
        self.loadingState = loadingState
        self.footerLoadingState = footerLoadingState
        self.fetchAction = fetchAction
        self.fetchMoreAction = fetchMoreAction
        self.navigateAction = navigateAction
        self.translateAction = translateAction
    }

    var body: some View {
        WaterfallCollectionView(
            galleries: galleries,
            setting: setting,
            translationRevision: translationRevision,
            datasetIdentity: datasetIdentity,
            presentations: presentations,
            actionsProvider: actionsProvider,
            pageNumber: pageNumber,
            loadingState: loadingState,
            footerLoadingState: footerLoadingState,
            fetchAction: fetchAction,
            fetchMoreAction: fetchMoreAction,
            navigateAction: navigateAction,
            translateAction: translateAction
        )
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .background(Color(uiColor: .systemGroupedBackground))
    }
}
