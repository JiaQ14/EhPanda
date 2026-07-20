//
//  GalleryCardCell.swift
//  EhPanda
//

import SwiftUI
import Kingfisher

struct GalleryCardCell: View {
    @Environment(\.displayScale) private var displayScale

    private let width: CGFloat
    private let height: CGFloat
    private let gallery: Gallery

    init(
        gallery: Gallery,
        width: CGFloat = Defaults.FrameSize.cardCellWidth,
        height: CGFloat = Defaults.FrameSize.cardCellHeight
    ) {
        self.gallery = gallery
        self.width = width
        self.height = height
    }
    private var title: String {
        let trimmedTitle = gallery.trimmedTitle
        guard width < 500, trimmedTitle.count > 20 else {
            return gallery.title
        }
        return trimmedTitle
    }
    private var usesAccessibilityLayout: Bool {
        height > Defaults.FrameSize.cardCellHeight
    }
    private var coverHeight: CGFloat {
        usesAccessibilityLayout ? 112 : Defaults.ImageSize.headerH
    }
    private var coverWidth: CGFloat {
        coverHeight * Defaults.ImageSize.headerAspect
    }
    private var coverPixelSize: CGSize {
        .init(width: coverWidth * displayScale, height: coverHeight * displayScale)
    }
    private var horizontalPadding: CGFloat {
        usesAccessibilityLayout ? 16 : 20
    }
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

        ZStack {
            HStack(spacing: usesAccessibilityLayout ? 12 : 15) {
                KFImage(gallery.coverURL)
                    .placeholder { Placeholder(style: .activity(ratio: Defaults.ImageSize.headerAspect)) }
                    .downsampling(size: coverPixelSize)
                    .backgroundDecode()
                    .loadDiskFileSynchronously(false)
                    .cancelOnDisappear(true)
                    .fade(duration: 0.15)
                    .resizable()
                    .scaledToFill()
                    .frame(width: coverWidth, height: coverHeight)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.title3.bold())
                        .lineLimit(usesAccessibilityLayout ? 5 : 4)
                    Spacer(minLength: 0)
                    RatingView(rating: gallery.rating).foregroundColor(.yellow)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, usesAccessibilityLayout ? 16 : 20)
        }
        .frame(width: width, height: height)
        .contentShape(shape)
        .background(.regularMaterial, in: shape)
        .overlay {
            shape.stroke(.primary.opacity(0.08), lineWidth: 0.5)
        }
        .hoverEffect(.highlight)
    }
}

struct GalleryCardCell_Previews: PreviewProvider {
    static var previews: some View {
        let gallery = Gallery.preview
        GalleryCardCell(
            gallery: gallery
        )
        .previewLayout(.fixed(width: 300, height: 206)).padding()
    }
}
