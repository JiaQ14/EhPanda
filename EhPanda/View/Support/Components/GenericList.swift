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
                    footerLoadingState: footerLoadingState, fetchMoreAction: fetchMoreAction,
                    navigateAction: navigateAction, translateAction: translateAction
                )
                .refreshable { fetchAction?() }
            case .thumbnail:
                WaterfallList(
                    galleries: galleries, setting: setting,
                    translationRevision: translationRevision,
                    datasetIdentity: datasetIdentity, pageNumber: pageNumber,
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
    private let footerLoadingState: LoadingState
    private let fetchMoreAction: (() -> Void)?
    private let navigateAction: ((String) -> Void)?
    private let translateAction: ((String) -> (String, TagTranslation?))?

    init(
        galleries: [Gallery], setting: Setting, pageNumber: PageNumber?,
        footerLoadingState: LoadingState,
        fetchMoreAction: (() -> Void)?,
        navigateAction: ((String) -> Void)? = nil,
        translateAction: ((String) -> (String, TagTranslation?))? = nil
    ) {
        self.galleries = galleries
        self.setting = setting
        self.pageNumber = pageNumber
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
        List(galleries) { gallery in
            Button {
                navigateAction?(gallery.id)
            } label: {
                GalleryDetailCell(gallery: gallery, setting: setting, translateAction: translateAction)
            }
            .buttonStyle(.plain)
            .listRowInsets(.init(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowSeparator(.visible)
            .onAppear {
                if gallery == galleries.last,
                   pageNumber?.hasNextPage() == true,
                   footerLoadingState == .idle
                {
                    fetchMoreAction?()
                }
            }
            if shouldShowFooter(gallery: gallery) {
                FetchMoreFooter(loadingState: footerLoadingState, retryAction: fetchMoreAction)
            }
        }
        .listStyle(.plain)
    }
}

// MARK: WaterfallList
private struct WaterfallList: View {
    private let galleries: [Gallery]
    private let setting: Setting
    private let translationRevision: TagTranslator.RenderRevision?
    private let datasetIdentity: AnyHashable
    private let pageNumber: PageNumber?
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
            pageNumber: pageNumber,
            loadingState: loadingState,
            footerLoadingState: footerLoadingState,
            fetchAction: fetchAction,
            fetchMoreAction: fetchMoreAction,
            navigateAction: navigateAction,
            translateAction: translateAction
        )
        .ignoresSafeArea(.container, edges: .top)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}
