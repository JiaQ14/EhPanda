//
//  GalleryListCard.swift
//  EhPanda
//

import SwiftUI
import UIKit
import Kingfisher

struct GalleryCardTag {
    let text: String
    let imageURL: URL?
    let foreground: Color
    let background: Color?
    var frame: CGRect
}

// The same font metrics and rectangles drive sizing and rendering. Images and
// keyboard transitions cannot feed a second measurement back into the list.
struct GalleryCardLayout {
    let width: CGFloat
    let titleFont: UIFont
    let bodyFont: UIFont
    let tagFont: UIFont
    var height: CGFloat = 0
    var cover = CGRect.zero
    var title = CGRect.zero
    var uploader = CGRect.zero
    var metadata = CGRect.zero
    var rating = CGRect.zero
    var category = CGRect.zero
    var date = CGRect.zero
    var status = CGRect.zero
    var tags = [GalleryCardTag]()

    init(
        gallery: Gallery, setting: Setting, presentation: GalleryListPresentation?,
        width: CGFloat, contentSize: UIContentSizeCategory, rightToLeft: Bool = false,
        translate: ((String) -> (String, TagTranslation?))?
    ) {
        self.width = max(1, width)
        let detail = setting.listDisplayMode == .detail
        let traits = UITraitCollection(preferredContentSizeCategory: contentSize)
        let baseTitle = UIFont.preferredFont(forTextStyle: detail ? .headline : .callout, compatibleWith: traits)
        titleFont = .systemFont(ofSize: baseTitle.pointSize, weight: .semibold)
        bodyFont = .preferredFont(forTextStyle: .footnote, compatibleWith: traits)
        tagFont = .preferredFont(forTextStyle: .caption2, compatibleWith: traits)
        let padding: CGFloat = detail ? 12 : 10
        if detail {
            let coverWidth = min(Defaults.ImageSize.rowW, self.width * 0.28)
            cover = CGRect(x: padding, y: padding, width: coverWidth, height: coverWidth / Defaults.ImageSize.rowAspect)
        } else {
            cover = CGRect(x: 0, y: 0, width: self.width, height: self.width / Defaults.ImageSize.rowAspect)
        }
        let x = detail ? cover.maxX + 12 : padding
        let textWidth = max(1, self.width - x - padding)
        var y = detail ? padding : cover.maxY + padding
        title = CGRect(x: x, y: y, width: textWidth,
                       height: Self.textHeight(gallery.title, font: titleFont, width: textWidth, lines: 3))
        y = title.maxY + 7
        if detail, let name = gallery.uploader, !name.isEmpty {
            uploader = CGRect(x: x, y: y, width: textWidth, height: ceil(bodyFont.lineHeight))
            y = uploader.maxY + 7
        }
        if setting.showsTagsInList {
            var tagX: CGFloat = 0
            var row = 0
            let tagHeight = ceil(tagFont.lineHeight) + 4
            for content in gallery.tagContents(maximum: setting.listTagsNumberMaximum) {
                let translation = translate?(content.rawNamespace + content.text).1
                let text = translation?.displayValue ?? content.text
                let imageURL = setting.showsImagesInTags ? translation?.valueImageURL : nil
                let textWidth = (text as NSString).size(withAttributes: [.font: tagFont]).width
                let tagWidth = min(title.width, ceil(textWidth) + 8 + (imageURL == nil ? 0 : tagHeight))
                if tagX > 0, tagX + tagWidth > title.width {
                    row += 1
                    tagX = 0
                }
                if !detail && row >= 4 { break }
                tags.append(.init(
                    text: text, imageURL: imageURL,
                    foreground: content.backgroundColor == nil ? .secondary : content.textColor ?? .secondary,
                    background: content.backgroundColor,
                    frame: CGRect(x: x + tagX, y: y + CGFloat(row) * (tagHeight + 4),
                                  width: tagWidth, height: tagHeight)
                ))
                tagX += tagWidth + 4
            }
            if let bottom = tags.last?.frame.maxY { y = bottom + 7 }
        }
        let lineHeight = ceil(bodyFont.lineHeight)
        metadata = CGRect(x: x, y: y, width: textWidth, height: lineHeight)
        rating = CGRect(x: x, y: metadata.maxY + 5, width: textWidth, height: lineHeight)
        y = rating.maxY + 7
        if detail {
            let categoryWidth = min(textWidth, ceil((gallery.category.value as NSString)
                .size(withAttributes: [.font: bodyFont]).width) + 12)
            category = CGRect(x: x, y: y, width: categoryWidth, height: lineHeight + 4)
            date = CGRect(x: category.maxX + 8, y: y, width: max(0, textWidth - categoryWidth - 8),
                          height: lineHeight + 4)
            y = category.maxY + 7
        } else {
            let categoryWidth = min(self.width, ceil((gallery.category.value as NSString)
                .size(withAttributes: [.font: bodyFont]).width) + 12)
            category = CGRect(x: self.width - categoryWidth, y: 0,
                              width: categoryWidth, height: lineHeight + 6)
        }
        if presentation?.status != nil {
            // Reserve the status slots while progress/message values change.
            status = CGRect(x: x, y: y, width: textWidth,
                            height: max(30, ceil(bodyFont.lineHeight)) + 24 + ceil(tagFont.lineHeight) * 3)
            y = status.maxY + 7
        }
        height = ceil(max(y + padding - 7, cover.maxY + (detail ? padding : 0)))
        if rightToLeft {
            let paths: [WritableKeyPath<Self, CGRect>] = [
                \.cover, \.title, \.uploader, \.metadata, \.rating, \.category, \.date, \.status
            ]
            for path in paths where self[keyPath: path].width > 0 {
                self[keyPath: path].origin.x = self.width - self[keyPath: path].maxX
            }
            tags = tags.map { tag in
                var tag = tag
                tag.frame.origin.x = self.width - tag.frame.maxX
                return tag
            }
        }
    }

    static func textHeight(_ text: String, font: UIFont, width: CGFloat, lines: Int) -> CGFloat {
        let measured = (text as NSString).boundingRect(
            with: CGSize(width: max(1, width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil
        ).height
        return ceil(min(CGFloat(lines) * font.lineHeight, max(font.lineHeight, measured)))
    }
}

struct GalleryListCard: View {
    @Environment(\.displayScale) private var displayScale
    let gallery: Gallery
    let presentation: GalleryListPresentation?
    let actions: [GalleryListAction]
    let layout: GalleryCardLayout

    private var coverURL: URL? { presentation?.coverURL ?? gallery.coverURL }

    var body: some View {
        ZStack(alignment: .topLeading) {
            KFImage(coverURL)
                .placeholder { Color(uiColor: .tertiarySystemFill) }
                .downsampling(size: CGSize(width: layout.cover.width * displayScale,
                                          height: layout.cover.height * displayScale))
                .backgroundDecode()
                .loadDiskFileSynchronously(false)
                .cancelOnDisappear(true)
                .cacheMemoryOnly(coverURL?.isFileURL == true)
                .resizable()
                .scaledToFill()
                .frame(width: layout.cover.width, height: layout.cover.height)
                .clipped()
                .offset(x: layout.cover.minX, y: layout.cover.minY)
            Text(gallery.title)
                .font(Font(layout.titleFont))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .cardFrame(layout.title)
            if layout.uploader.height > 0 {
                Label(gallery.uploader ?? "", systemImage: "person")
                    .font(Font(layout.bodyFont))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .cardFrame(layout.uploader)
            }
            ForEach(layout.tags.indices, id: \.self) { index in
                let tag = layout.tags[index]
                HStack(spacing: 2) {
                    if let url = tag.imageURL {
                        KFImage(url).loadDiskFileSynchronously(false).cancelOnDisappear(true)
                            .resizable().scaledToFit()
                            .frame(width: layout.tagFont.lineHeight, height: layout.tagFont.lineHeight)
                    }
                    Text(tag.text).lineLimit(1)
                }
                .font(Font(layout.tagFont))
                .foregroundStyle(tag.foreground)
                .padding(.horizontal, 4)
                .frame(width: tag.frame.width, height: tag.frame.height, alignment: .leading)
                .background(tag.background ?? Color(uiColor: .tertiarySystemFill),
                            in: RoundedRectangle(cornerRadius: 4))
                .offset(x: tag.frame.minX, y: tag.frame.minY)
            }
            HStack(spacing: 8) {
                if let language = gallery.language { Text(language.value) }
                Label(String(gallery.pageCount), systemImage: "photo.on.rectangle.angled")
            }
            .font(Font(layout.bodyFont)).foregroundStyle(.secondary).lineLimit(1)
            .cardFrame(layout.metadata)
            RatingView(rating: gallery.rating)
                .font(Font(layout.bodyFont)).foregroundStyle(.yellow).minimumScaleFactor(0.5)
                .cardFrame(layout.rating)
            Text(gallery.category.value)
                .font(Font(layout.bodyFont)).foregroundStyle(.white).lineLimit(1)
                .frame(width: layout.category.width, height: layout.category.height)
                .background(gallery.color)
                .offset(x: layout.category.minX, y: layout.category.minY)
            if layout.date.width > 0 {
                Text(gallery.formattedDateString)
                    .font(Font(layout.bodyFont)).foregroundStyle(.secondary).lineLimit(1)
                    .cardFrame(layout.date, alignment: .trailing)
            }
            if let status = presentation?.status {
                GalleryListStatusView(status: status, actions: actions, compact: false)
                    .cardFrame(layout.status)
            }
        }
        .frame(width: layout.width, height: layout.height, alignment: .topLeading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .hoverEffect(.highlight)
    }
}

private extension View {
    func cardFrame(_ rect: CGRect, alignment: Alignment = .topLeading) -> some View {
        frame(width: rect.width, height: rect.height, alignment: alignment)
            .clipped()
            .offset(x: rect.minX, y: rect.minY)
    }
}

extension DynamicTypeSize {
    var galleryContentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}
