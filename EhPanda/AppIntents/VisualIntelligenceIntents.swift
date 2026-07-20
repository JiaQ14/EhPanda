//
//  VisualIntelligenceIntents.swift
//  EhPanda
//

#if canImport(VisualIntelligence)
import AppIntents
import CoreImage
import VisualIntelligence

private enum SemanticContentImageRenderer {
    static let context = CIContext(options: [.cacheIntermediates: false])

    static func image(from descriptor: SemanticContentDescriptor) -> CGImage? {
        guard let pixelBuffer = descriptor.pixelBuffer else { return nil }
        return pixelBuffer.withUnsafeBuffer { buffer in
            let source = CIImage(cvPixelBuffer: buffer)
            return context.createCGImage(source, from: source.extent)
        }
    }
}

struct GalleryVisualIntentValueQuery: IntentValueQuery {
    @Dependency(default: GalleryVisualSearchService.shared)
    private var service: GalleryVisualSearchService

    func values(for input: SemanticContentDescriptor) async throws -> [GalleryEntity] {
        guard AppIntentPreferences.enablesVisualSearch,
              let image = SemanticContentImageRenderer.image(from: input)
        else { return [] }

        return await service.search(image: image, labels: input.labels).entities
    }
}

@AppIntent(schema: .visualIntelligence.semanticContentSearch)
struct SemanticGallerySearchIntent {
    static let title: LocalizedStringResource = "Search Galleries from Image"
    static let supportedModes: IntentModes = .foreground(.immediate)

    var semanticContent: SemanticContentDescriptor

    @Dependency(default: GalleryVisualSearchService.shared)
    private var service: GalleryVisualSearchService

    func perform() async throws -> some IntentResult {
        guard AppIntentPreferences.enablesVisualSearch,
              let image = SemanticContentImageRenderer.image(from: semanticContent)
        else { return .result() }

        let output = await service.search(image: image, labels: semanticContent.labels)
        AppIntentNavigationStore.shared.enqueue(output.navigationRoute)
        return .result()
    }
}
#endif
