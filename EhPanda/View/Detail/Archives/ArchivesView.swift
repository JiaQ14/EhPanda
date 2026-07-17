//
//  ArchivesView.swift
//  EhPanda
//

import SwiftUI
import ComposableArchitecture

struct ArchivesView: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable private var store: StoreOf<ArchivesReducer>
    private let gid: String
    private let user: User
    private let galleryURL: URL
    private let archiveURL: URL

    init(
        store: StoreOf<ArchivesReducer>,
        gid: String, user: User, galleryURL: URL, archiveURL: URL
    ) {
        self.store = store
        self.gid = gid
        self.user = user
        self.galleryURL = galleryURL
        self.archiveURL = archiveURL
    }

    // MARK: ArchiveView
    var body: some View {
        NavigationStack {
            ZStack {
                VStack {
                    HathArchivesView(archives: store.hathArchives, selection: $store.selectedArchive)

                    Spacer()

                    if let credits = Int(user.credits ?? ""), let galleryPoints = Int(user.galleryPoints ?? "") {
                        ArchiveFundsView(credits: credits, galleryPoints: galleryPoints)
                    }

                    DownloadButton(isDisabled: store.selectedArchive == nil) {
                        store.send(.fetchDownloadResponse(archiveURL))
                    }
                }
                .padding(.horizontal)
                .opacity(store.hathArchives.isEmpty ? 0 : 1)

                LoadingView()
                    .opacity(
                        store.loadingState == .loading
                        && store.hathArchives.isEmpty ? 1 : 0
                    )

                let error = store.loadingState.failed
                ErrorView(error: error ?? .unknown) {
                    store.send(.fetchArchive(gid, galleryURL, archiveURL))
                }
                .opacity(error != nil && store.hathArchives.isEmpty ? 1 : 0)
            }
            .progressHUD(
                config: store.communicatingHUDConfig,
                unwrapping: $store.route,
                case: \.communicatingHUD
            )
            .progressHUD(
                config: store.messageHUDConfig,
                unwrapping: $store.route,
                case: \.messageHUD
            )
            .animation(.default, value: store.hathArchives)
            .animation(.default, value: user.galleryPoints)
            .animation(.default, value: user.credits)
            .onAppear {
                store.send(.fetchArchive(gid, galleryURL, archiveURL))
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) {
                        dismiss()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(L10n.Localizable.ArchivesView.Title.archives)
        }
    }
}

// MARK: HathArchivesView
private struct HathArchivesView: View {
    private let archives: [GalleryArchive.HathArchive]
    @Binding private var selection: GalleryArchive.HathArchive?

    init(archives: [GalleryArchive.HathArchive], selection: Binding<GalleryArchive.HathArchive?>) {
        self.archives = archives
        _selection = selection
    }

    private let gridItems = [
        GridItem(.adaptive(
            minimum: Defaults.FrameSize.archiveGridWidth,
            maximum: Defaults.FrameSize.archiveGridWidth
        ))
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: gridItems, spacing: 10) {
                ForEach(archives) { archive in
                    Button {
                        selection = archive
                        HapticsUtil.generateFeedback(style: .soft)
                    } label: {
                        HathArchiveGrid(isSelected: selection == archive, archive: archive)
                            .tint(.primary).multilineTextAlignment(.center)
                    }
                    .disabled(!archive.isValid)
                    .accessibilityAddTraits(selection == archive ? .isSelected : [])
                }
            }
            .padding(.top, 16)
        }
    }
}

// MARK: ArchiveFundsView
private struct ArchiveFundsView: View {
    private let credits: Int
    private let galleryPoints: Int

    init(credits: Int, galleryPoints: Int) {
        self.credits = credits
        self.galleryPoints = galleryPoints
    }

    var body: some View {
        HStack(spacing: 20) {
            Label("\(galleryPoints)", systemSymbol: .gCircleFill)
            Label("\(credits)", systemSymbol: .cCircleFill)
        }
        .font(.headline).lineLimit(1).padding()
    }
}

// MARK: HathArchiveGrid
private struct HathArchiveGrid: View {
    private let isSelected: Bool
    private let archive: GalleryArchive.HathArchive

    private var disabledColor: Color {
        .gray.opacity(0.5)
    }
    private var fileSizeColor: Color {
        !archive.isValid ? disabledColor : .gray
    }
    private var borderColor: Color {
        !archive.isValid ? disabledColor : isSelected ? .accentColor : .gray
    }
    private var foregroundColor: Color? {
        !archive.isValid ? disabledColor : nil
    }
    private var width: CGFloat {
        Defaults.FrameSize.archiveGridWidth
    }
    private var height: CGFloat {
        width / 1.5
    }

    init(isSelected: Bool, archive: GalleryArchive.HathArchive) {
        self.isSelected = isSelected
        self.archive = archive
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(archive.resolution.value)
                .font(.title3.bold())

            VStack {
                Text(archive.fileSize)
                    .fontWeight(.medium)
                    .font(.caption)

                Text(archive.price)
                    .foregroundColor(fileSizeColor)
                    .font(.caption2)
            }
            .lineLimit(1)
        }
        .foregroundColor(foregroundColor)
        .frame(width: width, height: height)
        .contentShape(.rect)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
        .glassEffect(.clear.interactive(), in: .rect(cornerRadius: 8))
    }
}

// MARK: DownloadButton
private struct DownloadButton: View {
    private var isDisabled: Bool
    private var action: () -> Void

    init(isDisabled: Bool, action: @escaping () -> Void) {
        self.isDisabled = isDisabled
        self.action = action
    }

    private var paddingInsets: EdgeInsets {
        DeviceUtil.isPadWidth
            ? .init(top: 0, leading: 0, bottom: 30, trailing: 0)
            : .init(top: 0, leading: 10, bottom: 30, trailing: 10)
    }

    var body: some View {
        Button(action: action) {
            Text(L10n.Localizable.ArchivesView.Button.downloadToHathClient)
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.roundedRectangle(radius: 8))
        .controlSize(.large)
        .disabled(isDisabled)
        .padding(paddingInsets)
    }
}

struct ArchivesView_Previews: PreviewProvider {
    static var previews: some View {
        ArchivesView(
            store: .init(initialState: .init(), reducer: ArchivesReducer.init),
            gid: .init(),
            user: .init(),
            galleryURL: .mock,
            archiveURL: .mock
        )
    }
}
