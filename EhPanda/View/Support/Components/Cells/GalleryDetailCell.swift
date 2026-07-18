//
//  GalleryDetailCell.swift
//  EhPanda
//

import SwiftUI
import Kingfisher

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

struct GalleryDetailCell: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    private let gallery: Gallery
    private let setting: Setting
    private let presentation: GalleryListPresentation?
    private let actions: [GalleryListAction]
    private let translateAction: ((String) -> (String, TagTranslation?))?

    init(
        gallery: Gallery,
        setting: Setting,
        presentation: GalleryListPresentation? = nil,
        actions: [GalleryListAction] = [],
        translateAction: ((String) -> (String, TagTranslation?))? = nil
    ) {
        self.gallery = gallery
        self.setting = setting
        self.presentation = presentation
        self.actions = actions
        self.translateAction = translateAction
    }

    private var tagColor: Color {
        colorScheme == .light ? Color(.systemGray5) : Color(.systemGray4)
    }
    private var coverPixelSize: CGSize {
        .init(
            width: Defaults.ImageSize.rowW * displayScale,
            height: Defaults.ImageSize.rowH * displayScale
        )
    }
    private var coverURL: URL? {
        presentation?.coverURL ?? gallery.coverURL
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        HStack(alignment: .top, spacing: 12) {
            KFImage(coverURL)
                .placeholder { Placeholder(style: .activity(ratio: Defaults.ImageSize.rowAspect)) }
                .downsampling(size: coverPixelSize)
                .backgroundDecode()
                .loadDiskFileSynchronously(false)
                .cancelOnDisappear(true)
                .cacheMemoryOnly(coverURL?.isFileURL == true)
                .fade(duration: 0.15)
                .resizable()
                .scaledToFill()
                .frame(
                    width: Defaults.ImageSize.rowW,
                    height: Defaults.ImageSize.rowH
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 7) {
                Text(gallery.title)
                    .lineLimit(3)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if let uploader = gallery.uploader, !uploader.isEmpty {
                    Label(uploader, systemImage: "person")
                        .lineLimit(1)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                let tagContents = gallery.tagContents(maximum: setting.listTagsNumberMaximum)
                if setting.showsTagsInList, !tagContents.isEmpty {
                    TagCloudView(data: tagContents) { content in
                        let translation = translateAction?(content.rawNamespace + content.text).1
                        TagCloudCell(
                            text: translation?.displayValue ?? content.text,
                            imageURL: translation?.valueImageURL,
                            showsImages: setting.showsImagesInTags,
                            font: .caption2, padding: .init(top: 2, leading: 4, bottom: 2, trailing: 4),
                            textColor: content.backgroundColor != nil ? content.textColor ?? .secondary : .secondary,
                            backgroundColor: content.backgroundColor ?? tagColor
                        )
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    RatingView(rating: gallery.rating)
                        .font(.caption)
                        .foregroundStyle(.yellow)

                    Spacer(minLength: 4)

                    HStack(spacing: 10) {
                        if let language = gallery.language {
                            Text(language.value)
                        }
                        HStack(spacing: 2) {
                            Image(systemSymbol: .photoOnRectangleAngled)
                            Text(String(gallery.pageCount))
                        }
                    }
                    .lineLimit(1)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.75)
                }

                HStack(alignment: .center) {
                    CategoryLabel(text: gallery.category.value, color: gallery.color)
                    Spacer(minLength: 4)
                    Text(gallery.formattedDateString)
                        .lineLimit(1)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(0.75)
                }

                if let status = presentation?.status {
                    Divider()
                    GalleryListStatusView(
                        status: status,
                        actions: actions,
                        compact: false
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .contentShape(shape)
        .glassEffect(.regular.interactive(), in: shape)
        .overlay {
            shape.stroke(
                .primary.opacity(colorScheme == .light ? 0.06 : 0.12),
                lineWidth: 0.5
            )
        }
    }
}

struct GalleryDetailCell_Previews: PreviewProvider {
    static var previews: some View {
        GalleryDetailCell(gallery: .preview, setting: Setting())
    }
}
