//
//  GalleryRankingCell.swift
//  EhPanda
//

import SwiftUI
import Kingfisher

struct GalleryRankingCell: View, Equatable {
    @Environment(\.displayScale) private var displayScale

    private static let coverSize = CGSize(
        width: Defaults.ImageSize.rowW * 0.75,
        height: Defaults.ImageSize.rowH * 0.75
    )

    private let gallery: Gallery
    private let ranking: Int

    init(gallery: Gallery, ranking: Int) {
        self.gallery = gallery
        self.ranking = ranking
    }

    private var coverPixelSize: CGSize {
        .init(
            width: Self.coverSize.width * displayScale,
            height: Self.coverSize.height * displayScale
        )
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.ranking == rhs.ranking
            && lhs.gallery.id == rhs.gallery.id
            && lhs.gallery.title == rhs.gallery.title
            && lhs.gallery.uploader == rhs.gallery.uploader
            && lhs.gallery.coverURL == rhs.gallery.coverURL
    }

    var body: some View {
        HStack(spacing: 12) {
            KFImage(gallery.coverURL)
                .placeholder {
                    Placeholder(style: .activity(ratio: Defaults.ImageSize.headerAspect))
                }
                .downsampling(size: coverPixelSize)
                .backgroundDecode()
                .loadDiskFileSynchronously(false)
                .cancelOnDisappear(true)
                .resizable()
                .scaledToFill()
                .frame(width: Self.coverSize.width, height: Self.coverSize.height)
                .clipShape(.rect(cornerRadius: 4))

            Text(String(ranking))
                .font(.title2.weight(.medium))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(gallery.trimmedTitle)
                    .fontWeight(.bold)
                    .lineLimit(2)
                if let uploader = gallery.uploader {
                    Text(uploader)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .frame(height: Self.coverSize.height)
    }
}

struct GalleryRankingCell_Previews: PreviewProvider {
    static var previews: some View {
        GalleryRankingCell(gallery: .preview, ranking: 1)
            .previewLayout(.fixed(width: 300, height: 100))
            .preferredColorScheme(.dark)
    }
}
