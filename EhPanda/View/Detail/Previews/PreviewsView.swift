//
//  PreviewsView.swift
//  EhPanda
//

import SwiftUI
import Kingfisher
import ComposableArchitecture

struct PreviewsView: View {
    @Bindable private var store: StoreOf<PreviewsReducer>
    private let gid: String
    @Binding private var setting: Setting
    private let blurRadius: Double

    init(
        store: StoreOf<PreviewsReducer>,
        gid: String, setting: Binding<Setting>, blurRadius: Double
    ) {
        self.store = store
        self.gid = gid
        _setting = setting
        self.blurRadius = blurRadius
    }

    private var gridItems: [GridItem] {
        [GridItem(
            .adaptive(
                minimum: Defaults.ImageSize.previewMinW,
                maximum: Defaults.ImageSize.previewMaxW
            ),
            spacing: 10
        )]
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridItems, spacing: 10) {
                ForEach(1..<store.gallery.pageCount + 1, id: \.self) { index in
                    PreviewGridCell(
                        index: index,
                        originalURL: store.previewURLs[index],
                        selectAction: {
                            store.send(.updateReadingProgress(index))
                            store.send(.setNavigation(.reading()))
                        },
                        loadAction: {
                            store.send(.fetchPreviewURLs(index))
                        }
                    )
                    .equatable()
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .fullScreenCover(item: $store.route.sending(\.setNavigation).reading) { _ in
            ReadingView(
                store: store.scope(state: \.readingState, action: \.reading),
                gid: gid, setting: $setting, blurRadius: blurRadius
            )
            .accentColor(setting.accentColor)
            .autoBlur(radius: blurRadius)
        }
        .onAppear {
            store.send(.fetchDatabaseInfos(gid))
        }
        .navigationTitle(L10n.Localizable.PreviewsView.Title.previews)
    }
}

private struct PreviewGridCell: View, Equatable {
    @Environment(\.displayScale) private var displayScale

    private let index: Int
    private let originalURL: URL?
    private let selectAction: () -> Void
    private let loadAction: () -> Void

    init(
        index: Int,
        originalURL: URL?,
        selectAction: @escaping () -> Void,
        loadAction: @escaping () -> Void
    ) {
        self.index = index
        self.originalURL = originalURL
        self.selectAction = selectAction
        self.loadAction = loadAction
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.index == rhs.index && lhs.originalURL == rhs.originalURL
    }

    var body: some View {
        let resource = PreviewResolver.resolve(originalURL: originalURL)
        let targetWidth = ceil(Defaults.ImageSize.previewMaxW * displayScale)
        let targetPixelSize = CGSize(
            width: targetWidth,
            height: ceil(targetWidth / resource.aspectRatio)
        )

        VStack(spacing: 6) {
            Button(action: selectAction) {
                Color.clear
                    .aspectRatio(resource.aspectRatio, contentMode: .fit)
                    .overlay {
                        KFImage.url(resource.sourceURL)
                            .placeholder {
                                Placeholder(style: .activity(ratio: resource.aspectRatio))
                            }
                            .setProcessor(resource.processor(targetPixelSize: targetPixelSize))
                            .cacheOriginalImage()
                            .backgroundDecode()
                            .loadDiskFileSynchronously(false)
                            .cancelOnDisappear(true)
                            .resizable()
                            .scaledToFit()
                            .id(resource.originalURL?.absoluteString)
                    }
                    .clipShape(.rect(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            Text("\(index)")
                .font(DeviceUtil.isPadWidth ? .callout : .caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            guard originalURL == nil else { return }
            loadAction()
        }
    }
}

struct PreviewsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            PreviewsView(
                store: .init(initialState: .init(gallery: .preview), reducer: PreviewsReducer.init),
                gid: .init(),
                setting: .constant(.init()),
                blurRadius: 0
            )
        }
    }
}
