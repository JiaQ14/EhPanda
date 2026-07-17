//
//  GalleryThumbnailCell.swift
//  EhPanda
//

import SwiftUI
import Kingfisher

struct GalleryThumbnailCell: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    private let gallery: Gallery
    private let setting: Setting
    private let availableWidth: CGFloat
    private let translateAction: ((String) -> (String, TagTranslation?))?

    init(
        gallery: Gallery,
        setting: Setting,
        availableWidth: CGFloat = Defaults.ImageSize.rowW * 2,
        translateAction: ((String) -> (String, TagTranslation?))? = nil
    ) {
        self.gallery = gallery
        self.setting = setting
        self.availableWidth = availableWidth
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
            height: width / Defaults.ImageSize.webtoonMinAspect * displayScale
        )
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        VStack(alignment: .leading, spacing: 0) {
            KFImage(gallery.coverURL)
                .placeholder { Placeholder(style: .activity(ratio: Defaults.ImageSize.rowAspect)) }
                .downsampling(size: coverPixelSize)
                .backgroundDecode()
                .loadDiskFileSynchronously(false)
                .cancelOnDisappear(true)
                .imageModifier(WebtoonModifier(
                    minAspect: Defaults.ImageSize.webtoonMinAspect,
                    idealAspect: Defaults.ImageSize.webtoonIdealAspect
                ))
                .fade(duration: 0.15).resizable().scaledToFit().overlay {
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
            }
            .padding(10)
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
