//
//  GenericList.swift
//  EhPanda
//

import SwiftUI

struct GenericList: View {
    let galleries: [Gallery]
    let setting: Setting
    var translationRevision: TagTranslator.RenderRevision?
    var datasetIdentity: AnyHashable = 0
    var presentations: [String: GalleryListPresentation] = [:]
    var actionsProvider: ((String) -> [GalleryListAction])?
    let pageNumber: PageNumber?
    let loadingState: LoadingState
    let footerLoadingState: LoadingState
    var fetchAction: (() async -> Void)?
    var fetchMoreAction: (() -> Void)?
    var navigateAction: ((String) -> Void)?
    var translateAction: ((String) -> (String, TagTranslation?))?

    var body: some View {
        GalleryListView(
            galleries: galleries, setting: setting,
            translationRevision: translationRevision, datasetIdentity: datasetIdentity,
            presentations: presentations, actionsProvider: actionsProvider,
            pageNumber: pageNumber, loadingState: loadingState, footerLoadingState: footerLoadingState,
            fetchAction: fetchAction, fetchMoreAction: fetchMoreAction,
            navigateAction: navigateAction, translateAction: translateAction
        )
        // SwiftUI owns the viewport; the native list never also adjusts navigation insets.
        .clipped()
        .background(Color(uiColor: .systemGroupedBackground))
        .overlay {
            if galleries.isEmpty && loadingState == .loading {
                LoadingView()
            } else if galleries.isEmpty, let error = loadingState.failed {
                if let fetchAction {
                    ErrorView(error: error) { Task { await fetchAction() } }
                } else {
                    ErrorView(error: error)
                }
            }
        }
    }
}
