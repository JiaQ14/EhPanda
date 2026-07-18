//
//  GalleryThumbnailCell.swift
//  EhPanda
//

import SwiftUI
import Kingfisher

struct GalleryThumbnailCell: View {
    static let statusInformationHeight: CGFloat = 68

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    private let gallery: Gallery
    private let setting: Setting
    private let availableWidth: CGFloat
    private let informationHeight: CGFloat
    private let presentation: GalleryListPresentation?
    private let actions: [GalleryListAction]
    private let translateAction: ((String) -> (String, TagTranslation?))?

    init(
        gallery: Gallery,
        setting: Setting,
        availableWidth: CGFloat = Defaults.ImageSize.rowW * 2,
        informationHeight: CGFloat? = nil,
        presentation: GalleryListPresentation? = nil,
        actions: [GalleryListAction] = [],
        translateAction: ((String) -> (String, TagTranslation?))? = nil
    ) {
        self.gallery = gallery
        self.setting = setting
        self.availableWidth = availableWidth
        self.presentation = presentation
        self.actions = actions
        self.informationHeight = informationHeight
            ?? Self.informationHeight(
                gallery: gallery,
                setting: setting,
                availableWidth: availableWidth,
                presentation: presentation,
                translateAction: translateAction
            )
        self.translateAction = translateAction
    }

    private var backgroundColor: Color {
        Color(uiColor: .secondarySystemGroupedBackground)
    }
    private var tagColor: Color {
        colorScheme == .light ? Color(.systemGray5) : Color(.systemGray4)
    }
    private var coverPixelSize: CGSize {
        let width = max(availableWidth, 1)
        return .init(
            width: width * displayScale,
            height: width / Defaults.ImageSize.rowAspect * displayScale
        )
    }
    private var coverURL: URL? {
        presentation?.coverURL ?? gallery.coverURL
    }

    static func informationHeight(
        gallery: Gallery,
        setting: Setting,
        availableWidth: CGFloat,
        presentation: GalleryListPresentation? = nil,
        translateAction: ((String) -> (String, TagTranslation?))? = nil
    ) -> CGFloat {
        let contentWidth = max(availableWidth - 20, 1)
        let titleCharactersPerLine = max(Int(contentWidth / 8), 1)
        let titleLines = min(
            3,
            max(1, Int(ceil(Double(gallery.title.count) / Double(titleCharactersPerLine))))
        )
        var height = 68 + CGFloat(titleLines) * 18

        let tagContents = gallery.tagContents(maximum: setting.listTagsNumberMaximum)
        if setting.showsTagsInList, !tagContents.isEmpty {
            var rowCount = 1
            var rowWidth = CGFloat.zero
            for content in tagContents {
                let translation = translateAction?(content.rawNamespace + content.text).1
                let text = translation?.displayValue ?? content.text
                let imageWidth: CGFloat =
                    setting.showsImagesInTags && translation?.valueImageURL != nil ? 14 : 0
                let tagWidth = min(
                    contentWidth,
                    max(24, CGFloat(text.count) * 6.5 + imageWidth + 8)
                )
                if rowWidth > 0, rowWidth + 4 + tagWidth > contentWidth {
                    rowCount += 1
                    rowWidth = tagWidth
                } else {
                    rowWidth += (rowWidth > 0 ? 4 : 0) + tagWidth
                }
                if rowCount == 4 { break }
            }

            let visibleRowCount = min(rowCount, 4)
            height += 5
                + CGFloat(visibleRowCount) * 18
                + CGFloat(max(visibleRowCount - 1, 0)) * 4
        }

        if presentation?.status != nil {
            height += statusInformationHeight
        }

        return ceil(height)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        VStack(alignment: .leading, spacing: 0) {
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
                    width: availableWidth,
                    height: availableWidth / Defaults.ImageSize.rowAspect
                )
                .clipped()
                .overlay {
                    VStack {
                        HStack {
                            Spacer()
                            CategoryLabel(
                                text: gallery.category.value, color: gallery.color,
                                insets: .init(top: 3, leading: 6, bottom: 3, trailing: 6),
                                cornerRadius: 6, corners: .bottomLeft
                            )
                        }
                        Spacer()
                    }
                }
            VStack(alignment: .leading, spacing: 5) {
                Text(gallery.title).font(.callout.weight(.semibold)).lineLimit(3)
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
                HStack(spacing: 10) {
                    if let language = gallery.language {
                        Text(language.value)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    HStack(spacing: 2) {
                        Image(systemSymbol: .photoOnRectangleAngled)
                        Text(String(gallery.pageCount))
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                }
                .lineLimit(1).font(.footnote).foregroundStyle(.secondary)
                RatingView(rating: gallery.rating).foregroundColor(.yellow).font(.caption)

                if let status = presentation?.status {
                    Divider()
                    GalleryListStatusView(
                        status: status,
                        actions: actions,
                        compact: true
                    )
                    .frame(
                        height: Self.statusInformationHeight - 10,
                        alignment: .top
                    )
                    .clipped()
                }
            }
            .padding(10)
            .frame(height: informationHeight, alignment: .top)
            .clipped()
        }
        .background(backgroundColor)
        .clipShape(shape)
        .overlay {
            shape.stroke(.primary.opacity(colorScheme == .light ? 0.08 : 0.14), lineWidth: 0.5)
        }
        .contentShape(shape)
    }
}

struct GalleryThumbnailCell_Previews: PreviewProvider {
    static var previews: some View {
        GalleryThumbnailCell(gallery: .preview, setting: Setting())
            .preferredColorScheme(.dark)
    }
}
