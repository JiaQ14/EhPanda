//
//  GalleryVisualSearchService.swift
//  EhPanda
//

import CoreGraphics
import Foundation
import Vision

struct VisualGallerySearchOutput: Sendable {
    let query: String
    let entities: [GalleryEntity]

    var navigationRoute: AppIntentRoute {
        if let entity = entities.first {
            return .gallery(gid: entity.id, readingProgress: nil)
        }
        return query.isEmpty ? .section(.search) : .search(query)
    }
}

struct GalleryRecognizedLine: Equatable, Sendable {
    let text: String
    let confidence: Float
    let isTitle: Bool
}

enum GallerySearchTextExtractor {
    private static let ignoredExactValues = Set([
        "back", "menu", "more", "read", "reading", "favorite", "favorites",
        "返回", "菜单", "更多", "阅读", "收藏", "评分", "页数"
    ])

    static func queries(from lines: [GalleryRecognizedLine], limit: Int = 3) -> [String] {
        var seen = Set<String>()
        return lines
            .filter { $0.confidence >= 0.25 }
            .compactMap { line -> (String, Int)? in
                let text = clean(line.text)
                guard text.count >= 2,
                      text.count <= 120,
                      !ignoredExactValues.contains(text.lowercased()),
                      text.unicodeScalars.contains(where: CharacterSet.letters.contains)
                else { return nil }
                let score = (line.isTitle ? 1_000 : 0) + Int(line.confidence * 100)
                    + min(text.count, 100)
                return (text, score)
            }
            .sorted { $0.1 > $1.1 }
            .compactMap { text, _ in
                seen.insert(text.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                )).inserted ? text : nil
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func clean(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}

enum GalleryVisualSearchRanker {
    static func textScore(title: String, queries: [String]) -> Double {
        queries.map { similarity(title, $0) }.max() ?? 0
    }

    static func combinedScore(text: Double, imageDistance: Double?) -> Double {
        guard let imageDistance else { return text }
        let image = 1 / (1 + max(imageDistance, 0))
        return text > 0 ? text * 0.72 + image * 0.28 : image
    }

    private static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let lhs = normalized(lhs)
        let rhs = normalized(rhs)
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        if lhs == rhs { return 1 }
        if lhs.contains(rhs) || rhs.contains(lhs) {
            return Double(min(lhs.count, rhs.count)) / Double(max(lhs.count, rhs.count))
        }

        let lhsBigrams = bigrams(lhs)
        let rhsBigrams = bigrams(rhs)
        guard !lhsBigrams.isEmpty, !rhsBigrams.isEmpty else { return 0 }
        let overlap = lhsBigrams.intersection(rhsBigrams).count
        return 2 * Double(overlap) / Double(lhsBigrams.count + rhsBigrams.count)
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private static func bigrams(_ value: String) -> Set<String> {
        let characters = Array(value)
        guard characters.count > 1 else { return Set([value]) }
        return Set(zip(characters, characters.dropFirst()).map {
            String([$0.0, $0.1])
        })
    }
}

enum GalleryVisualSearchImageLoader {
    static func data(from url: URL, session: URLSession) async -> Data? {
        if url.isFileURL {
            return await Task.detached(priority: .utility) {
                try? Data(contentsOf: url, options: .mappedIfSafe)
            }
            .value
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        guard let (data, response) = try? await session.data(for: request),
              let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode)
        else { return nil }
        return data
    }
}

final class GalleryVisualSearchService: @unchecked Sendable {
    static let shared = GalleryVisualSearchService()

    private let galleryService: IntentGalleryService
    private let databaseClient: DatabaseClient
    private let session: URLSession

    init(
        galleryService: IntentGalleryService = .shared,
        databaseClient: DatabaseClient = .live,
        session: URLSession = .shared
    ) {
        self.galleryService = galleryService
        self.databaseClient = databaseClient
        self.session = session
    }

    func search(image: CGImage, labels: [String] = []) async -> VisualGallerySearchOutput {
        guard AppIntentPreferences.enablesVisualSearch else {
            return .init(query: "", entities: [])
        }

        let lines = await recognizeText(in: image)
        let queries = GallerySearchTextExtractor.queries(from: lines)
        var candidates = await galleryService.visualCandidates()
        candidates.append(contentsOf: await remoteCandidates(for: queries))

        var seen = Set<String>()
        candidates = candidates.filter { seen.insert($0.id).inserted }
        let targetFeature = try? await GenerateImageFeaturePrintRequest().perform(on: image)
        let prioritized = candidates
            .map {
                (
                    entity: $0,
                    textScore: GalleryVisualSearchRanker.textScore(
                        title: $0.title,
                        queries: queries
                    )
                )
            }
            .sorted { $0.textScore > $1.textScore }
            .prefix(24)
        let scored = await scoreCandidates(
            prioritized,
            targetFeature: targetFeature
        )

        let entities = scored.sorted { $0.1 > $1.1 }.prefix(5).map(\.0)
        return .init(query: queries.first ?? labels.first ?? "", entities: entities)
    }

    private func scoreCandidates(
        _ candidates: some Sequence<(entity: GalleryEntity, textScore: Double)>,
        targetFeature: FeaturePrintObservation?
    ) async -> [(GalleryEntity, Double)] {
        await withTaskGroup(of: (GalleryEntity, Double)?.self) { group in
            let candidates = Array(candidates)
            let initialTaskCount = min(candidates.count, 6)
            var nextIndex = initialTaskCount

            for candidate in candidates.prefix(initialTaskCount) {
                group.addTask { [self] in
                    await scoreCandidate(candidate, targetFeature: targetFeature)
                }
            }

            var results = [(GalleryEntity, Double)]()
            while let result = await group.next() {
                if let result {
                    results.append(result)
                }
                if nextIndex < candidates.count {
                    let candidate = candidates[nextIndex]
                    nextIndex += 1
                    group.addTask { [self] in
                        await scoreCandidate(candidate, targetFeature: targetFeature)
                    }
                }
            }
            return results
        }
    }

    private func scoreCandidate(
        _ candidate: (entity: GalleryEntity, textScore: Double),
        targetFeature: FeaturePrintObservation?
    ) async -> (GalleryEntity, Double)? {
        let imageDistance = await featureDistance(
            from: targetFeature,
            to: candidate.entity.coverURL
        )
        let score = GalleryVisualSearchRanker.combinedScore(
            text: candidate.textScore,
            imageDistance: imageDistance
        )
        return score >= 0.2 ? (candidate.entity, score) : nil
    }

    private func recognizeText(in image: CGImage) async -> [GalleryRecognizedLine] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        guard let observations = try? await request.perform(on: image) else { return [] }
        return observations.map {
            GalleryRecognizedLine(
                text: $0.transcript,
                confidence: $0.confidence,
                isTitle: $0.isTitle
            )
        }
    }

    private func remoteCandidates(for queries: [String]) async -> [GalleryEntity] {
        guard !queries.isEmpty else { return [] }
        let filter = await MainActor.run {
            databaseClient.fetchFilterSynchronously(range: .search)
        }
        var galleries = [Gallery]()
        for query in queries.prefix(2) {
            let result = await SearchGalleriesRequest(keyword: query, filter: filter).response()
            if case .success((_, let matches)) = result {
                galleries.appendUniqueGalleries(matches)
            }
        }
        if !galleries.isEmpty {
            await databaseClient.cacheGalleries(galleries)
        }
        return galleries.map(GalleryEntity.init)
    }

    private func featureDistance(
        from target: FeaturePrintObservation?,
        to coverURL: URL?
    ) async -> Double? {
        guard let target, let coverURL,
              let data = await GalleryVisualSearchImageLoader.data(
                from: coverURL,
                session: session
              ),
              let candidate = try? await GenerateImageFeaturePrintRequest().perform(on: data)
        else { return nil }
        return try? target.distance(to: candidate)
    }
}
