//
//  TagCloudView.swift
//  EhPanda
//
//  Copied from https://stackoverflow.com/questions/62102647/
//

import SwiftUI
import Kingfisher

struct TagCloudView<Element, ID, TagCell>: View
where TagCell: View, Element: Equatable & Identifiable, ID == Element.ID {
    private let data: [Element]
    private let id: KeyPath<Element, ID>
    private let spacing: Double
    private let content: (Element) -> TagCell

    init<Data: RandomAccessCollection>(
        data: Data, id: KeyPath<Element, ID> = \Element.id, spacing: Double = 4,
        @ViewBuilder content: @escaping (Element) -> TagCell
    ) where Data.Index == Int, Data.Element == Element {
        self.data = .init(data)
        self.id = id
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        TagCloudLayout(spacing: spacing) {
            ForEach(data, id: id) { element in
                content(element)
            }
        }
    }
}

private struct TagCloudLayout: Layout {
    typealias Cache = TagCloudLayoutCache

    let spacing: CGFloat

    func makeCache(subviews: Subviews) -> Cache {
        .init()
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = .init()
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        let result = layout(
            subviews: subviews,
            width: proposal.width ?? .greatestFiniteMagnitude,
            cache: &cache
        )
        return .init(
            width: proposal.width ?? result.contentWidth,
            height: result.contentHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        let result = layout(
            subviews: subviews,
            width: bounds.width,
            cache: &cache
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: .init(
                    x: bounds.minX + result.origins[index].x,
                    y: bounds.minY + result.origins[index].y
                ),
                anchor: .topLeading,
                proposal: .init(result.sizes[index])
            )
        }
    }

    private func layout(
        subviews: Subviews,
        width: CGFloat,
        cache: inout Cache
    ) -> TagCloudLayoutResult {
        let availableWidth = max(width, 0)
        let key = TagCloudLayoutCache.Key(
            availableWidth: availableWidth,
            spacing: spacing,
            subviewCount: subviews.count
        )
        if cache.key == key, let result = cache.result {
            return result
        }

        var origins = [CGPoint]()
        var sizes = [CGSize]()
        var currentX = CGFloat.zero
        var currentY = CGFloat.zero
        var rowHeight = CGFloat.zero
        var contentWidth = CGFloat.zero

        for subview in subviews {
            let proposedWidth = availableWidth.isFinite ? availableWidth : nil
            let size = subview.sizeThatFits(
                .init(width: proposedWidth, height: nil)
            )
            if currentX > 0, currentX + size.width > availableWidth {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            origins.append(.init(x: currentX, y: currentY))
            sizes.append(size)
            contentWidth = max(contentWidth, currentX + size.width)
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        let result = TagCloudLayoutResult(
            origins: origins,
            sizes: sizes,
            contentWidth: contentWidth,
            contentHeight: subviews.isEmpty ? 0 : currentY + rowHeight
        )
        cache = .init(key: key, result: result)
        return result
    }
}

private struct TagCloudLayoutCache {
    struct Key: Equatable {
        let availableWidth: CGFloat
        let spacing: CGFloat
        let subviewCount: Int
    }

    var key: Key?
    var result: TagCloudLayoutResult?
}

private struct TagCloudLayoutResult {
    let origins: [CGPoint]
    let sizes: [CGSize]
    let contentWidth: CGFloat
    let contentHeight: CGFloat
}

struct TagCloudCell: View {
    private let text: String
    private let imageURL: URL?
    private let showsImages: Bool
    private let font: Font
    private let padding: EdgeInsets
    private let textColor: Color
    private let backgroundColor: Color

    init(
        text: String, imageURL: URL?, showsImages: Bool, font: Font,
        padding: EdgeInsets, textColor: Color, backgroundColor: Color
    ) {
        self.text = text
        self.imageURL = imageURL
        self.showsImages = showsImages
        self.font = font
        self.padding = padding
        self.textColor = textColor
        self.backgroundColor = backgroundColor
    }

    var body: some View {
        HStack(spacing: 2) {
            Text(showsImages ? text : text.emojisRipped)
            if let imageURL = imageURL, showsImages {
                Image(systemSymbol: .photo).opacity(0)
                    .overlay(KFImage(imageURL).resizable().scaledToFit())
            }
        }
        .font(font.bold()).lineLimit(1).foregroundColor(textColor)
        .padding(padding).background(backgroundColor).cornerRadius(5)
    }
}
