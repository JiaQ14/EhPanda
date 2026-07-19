//
//  ReaderImageProcessorTests.swift
//  EhPandaTests
//

import ImageIO
import Kingfisher
import UIKit
import XCTest
@testable import EhPanda

private enum ReaderImageProcessorTestError: Error {
    case fixtureCreationFailed
}

final class ReaderImageProcessorTests: XCTestCase {
    func testDetectsAnimatedFormatsFromDataInsteadOfURL() {
        let gifHeader = Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])
        let webPHeader = Data([
            0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0,
            0x57, 0x45, 0x42, 0x50
        ])

        XCTAssertEqual(ReaderAnimatedImageFormat(data: gifHeader), .gif)
        XCTAssertEqual(ReaderAnimatedImageFormat(data: webPHeader), .webP)
        XCTAssertNil(
            ReaderAnimatedImageFormat(
                data: Data([0x89, 0x50, 0x4E, 0x47])
            )
        )
    }

    func testAnimatedGIFSurvivesProcessingAndCacheSerialization() throws {
        let data = try makeAnimatedGIF()
        let processor = ReaderImageProcessor(
            targetPixelSize: CGSize(width: 16, height: 16)
        )
        let options = KingfisherParsedOptionsInfo([
            .processor(processor)
        ])
        let image = try XCTUnwrap(
            processor.process(item: .data(data), options: options)
        )

        XCTAssertEqual(image.kf.frameSource?.frameCount, 2)
        XCTAssertEqual(ReaderAnimatedImageData(image: image)?.format, .gif)

        let serializer = ReaderImageCacheSerializer()
        let cachedData = try XCTUnwrap(
            serializer.data(with: image, original: data)
        )
        XCTAssertEqual(cachedData, data)

        let restoredImage = try XCTUnwrap(
            serializer.image(with: cachedData, options: options)
        )
        XCTAssertEqual(restoredImage.kf.frameSource?.frameCount, 2)
    }

    private func makeAnimatedGIF() throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            "com.compuserve.gif" as CFString,
            2,
            nil
        ) else {
            throw ReaderImageProcessorTestError.fixtureCreationFailed
        }
        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: 0.1
            ]
        ]
        CGImageDestinationAddImage(
            destination,
            try makeImage(red: 0),
            frameProperties as CFDictionary
        )
        CGImageDestinationAddImage(
            destination,
            try makeImage(red: 1),
            frameProperties as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw ReaderImageProcessorTestError.fixtureCreationFailed
        }
        return output as Data
    }

    private func makeImage(red: CGFloat) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ReaderImageProcessorTestError.fixtureCreationFailed
        }
        context.setFillColor(red: red, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        guard let image = context.makeImage() else {
            throw ReaderImageProcessorTestError.fixtureCreationFailed
        }
        return image
    }
}
