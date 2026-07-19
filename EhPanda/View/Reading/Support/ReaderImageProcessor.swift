//
//  ReaderImageProcessor.swift
//  EhPanda
//

import ImageIO
import Kingfisher
import UIKit
import UniformTypeIdentifiers

enum ReaderAnimatedImageFormat: Equatable {
    case gif
    case webP

    init?(data: Data) {
        if data.starts(with: [0x47, 0x49, 0x46]) {
            self = .gif
        } else if data.count >= 12,
                  data.starts(with: [0x52, 0x49, 0x46, 0x46]),
                  data[8..<12].elementsEqual([0x57, 0x45, 0x42, 0x50])
        {
            self = .webP
        } else {
            return nil
        }
    }

    var typeIdentifier: String {
        switch self {
        case .gif:
            return UTType.gif.identifier
        case .webP:
            return UTType.webP.identifier
        }
    }
}

struct ReaderAnimatedImageData {
    let format: ReaderAnimatedImageFormat
    let data: Data

    init?(data: Data) {
        guard let format = ReaderAnimatedImageFormat(data: data),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 1
        else {
            return nil
        }
        self.format = format
        self.data = data
    }

    init?(image: UIImage) {
        guard let data = image.kf.frameSource?.data else { return nil }
        self.init(data: data)
    }
}

struct ReaderImageProcessor: ImageProcessor {
    let targetPixelSize: CGSize

    var identifier: String {
        let width = Int(targetPixelSize.width.rounded())
        let height = Int(targetPixelSize.height.rounded())
        return "com.ehpanda.reader-image-v1-\(width)x\(height)"
    }

    func process(
        item: ImageProcessItem,
        options: KingfisherParsedOptionsInfo
    ) -> UIImage? {
        switch item {
        case .data(let data):
            if let image = makeAnimatedImage(data: data, options: options) {
                return image
            }
            return processStatic(item: item, options: options)

        case .image(let image):
            if let data = image.kf.frameSource?.data,
               let animatedImage = makeAnimatedImage(data: data, options: options)
            {
                return animatedImage
            }
            return processStatic(item: item, options: options)
        }
    }

    private func makeAnimatedImage(
        data: Data,
        options: KingfisherParsedOptionsInfo
    ) -> UIImage? {
        guard let source = ReaderAnimatedImageFrameSource(
            data: data,
            targetPixelSize: targetPixelSize
        )
        else {
            return nil
        }
        return KingfisherWrapper<UIImage>.animatedImage(
            source: source,
            options: ImageCreatingOptions(
                scale: options.scaleFactor,
                preloadAll: options.preloadAllAnimationData,
                onlyFirstFrame: options.onlyLoadFirstFrame
            )
        )
    }

    private func processStatic(
        item: ImageProcessItem,
        options: KingfisherParsedOptionsInfo
    ) -> UIImage? {
        guard targetPixelSize.width > 0, targetPixelSize.height > 0 else {
            return DefaultImageProcessor.default.process(
                item: item,
                options: options
            )
        }
        return DownsamplingImageProcessor(size: targetPixelSize).process(
            item: item,
            options: options
        )
    }
}

struct ReaderImageCacheSerializer: CacheSerializer {
    private let defaultSerializer = DefaultCacheSerializer.default

    func data(with image: UIImage, original: Data?) -> Data? {
        if let original, ReaderAnimatedImageData(data: original) != nil {
            return original
        }
        if let animatedData = ReaderAnimatedImageData(image: image)?.data {
            return animatedData
        }
        return defaultSerializer.data(with: image, original: original)
    }

    func image(
        with data: Data,
        options: KingfisherParsedOptionsInfo
    ) -> UIImage? {
        if ReaderAnimatedImageData(data: data) != nil {
            let processor = options.processor as? ReaderImageProcessor
                ?? ReaderImageProcessor(targetPixelSize: .zero)
            return processor.process(item: .data(data), options: options)
        }
        return defaultSerializer.image(with: data, options: options)
    }
}

private struct ReaderAnimatedImageFrameSource: ImageFrameSource {
    let data: Data?
    let imageSource: CGImageSource
    let targetPixelSize: CGSize
    let format: ReaderAnimatedImageFormat

    init?(data: Data, targetPixelSize: CGSize) {
        guard let format = ReaderAnimatedImageFormat(data: data),
              let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(imageSource) > 1
        else {
            return nil
        }
        self.data = data
        self.imageSource = imageSource
        self.targetPixelSize = targetPixelSize
        self.format = format
    }

    var frameCount: Int {
        CGImageSourceGetCount(imageSource)
    }

    func frame(at index: Int, maxSize: CGSize?) -> CGImage? {
        let maximumPixelSize = [
            targetPixelSize.maximumDimension,
            maxSize?.maximumDimension ?? 0
        ]
        .filter { $0 > 0 }
        .min()

        guard let maximumPixelSize else {
            return CGImageSourceCreateImageAtIndex(imageSource, index, nil)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(
            imageSource,
            index,
            options as CFDictionary
        )
    }

    func duration(at index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(
            imageSource,
            index,
            nil
        ) as? [CFString: Any]
        else {
            return Self.defaultFrameDuration
        }

        let dictionaryKey: CFString
        let unclampedDelayKey: CFString
        let delayKey: CFString
        switch format {
        case .gif:
            dictionaryKey = kCGImagePropertyGIFDictionary
            unclampedDelayKey = kCGImagePropertyGIFUnclampedDelayTime
            delayKey = kCGImagePropertyGIFDelayTime
        case .webP:
            dictionaryKey = kCGImagePropertyWebPDictionary
            unclampedDelayKey = kCGImagePropertyWebPUnclampedDelayTime
            delayKey = kCGImagePropertyWebPDelayTime
        }

        guard let frameProperties = properties[dictionaryKey]
                as? [CFString: Any]
        else {
            return Self.defaultFrameDuration
        }
        let duration = (
            frameProperties[unclampedDelayKey]
                ?? frameProperties[delayKey]
        ) as? NSNumber
        guard let duration else {
            return Self.defaultFrameDuration
        }
        return duration.doubleValue > 0.011
            ? duration.doubleValue
            : Self.defaultFrameDuration
    }

    private static let defaultFrameDuration: TimeInterval = 0.1
}

private extension CGSize {
    var maximumDimension: CGFloat {
        max(width, height)
    }
}
