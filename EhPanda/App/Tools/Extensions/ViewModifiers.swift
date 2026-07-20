//
//  ViewModifiers.swift
//  EhPanda
//

import SwiftUI
import Kingfisher

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }

    @ViewBuilder func withHorizontalSpacing(width: CGFloat = 8, height: CGFloat? = nil) -> some View {
        Color.clear.frame(width: width, height: height)
        self
        Color.clear.frame(width: width, height: height)
    }

    func withArrow(isVisible: Bool = true) -> some View {
        HStack {
            self
            Spacer()
            Image(systemSymbol: .chevronRight)
                .foregroundColor(.secondary)
                .imageScale(.small)
                .opacity(isVisible ? 0.5 : 0)
        }
    }

    func autoBlur(radius: Double) -> some View {
        blur(radius: radius)
            .allowsHitTesting(radius < 1)
            .animation(.linear(duration: 0.1), value: radius)
    }

    func synchronize<Value: Equatable>(
        _ first: Binding<Value>,
        _ second: Binding<Value>,
        initial: (first: Bool, second: Bool) = (false, false)
    ) -> some View {
        self
            .onChange(of: first.wrappedValue, initial: initial.first) { _, newValue in
                second.wrappedValue = newValue
            }
            .onChange(of: second.wrappedValue, initial: initial.second) { _, newValue in
                first.wrappedValue = newValue
            }
    }

    func synchronize<Value>(
        _ first: Binding<Value>,
        _ second: FocusState<Value>.Binding,
        initial: (first: Bool, second: Bool) = (false, false)
    ) -> some View {
        self
            .onChange(of: first.wrappedValue, initial: initial.first) { _, newValue in
                second.wrappedValue = newValue
            }
            .onChange(of: second.wrappedValue, initial: initial.second) { _, newValue in
                first.wrappedValue = newValue
            }
    }

    func adaptiveGalleryDetail<Detail: View>(
        selection: Binding<String?>,
        blurRadius: Double,
        @ViewBuilder detail: @escaping (String) -> Detail
    ) -> some View {
        modifier(
            AdaptiveGalleryDetailModifier(
                selection: selection,
                blurRadius: blurRadius,
                detail: detail
            )
        )
    }

    func gallerySheetPresentation(
        gid: String,
        blurRadius: Double,
        onDetached: @escaping () -> Void
    ) -> some View {
        modifier(
            GallerySheetPresentationModifier(
                gid: gid,
                blurRadius: blurRadius,
                onDetached: onDetached
            )
        )
    }

    func embeddedInNavigationStack(_ embeds: Bool) -> some View {
        modifier(EmbeddedNavigationStackModifier(embeds: embeds))
    }
}

private struct EmbeddedNavigationStackModifier: ViewModifier {
    let embeds: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if embeds {
            NavigationStack {
                content
            }
        } else {
            content
        }
    }
}

private struct AdaptiveGalleryDetailModifier<Detail: View>: ViewModifier {
    @Binding var selection: String?

    let blurRadius: Double
    let detail: (String) -> Detail

    @ViewBuilder
    func body(content: Content) -> some View {
        if DeviceUtil.isPhone {
            content.navigationDestination(item: $selection) { gid in
                detail(gid)
                    .id(gid)
            }
        } else {
            content
                .sheet(item: $selection, id: \.self) { route in
                    let gid = route.wrappedValue
                    NavigationStack {
                        detail(gid)
                            .id(gid)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button(role: .cancel) {
                                        selection = nil
                                    } label: {
                                        Image(systemSymbol: .xmark)
                                    }
                                }
                            }
                    }
                    .gallerySheetPresentation(
                        gid: gid,
                        blurRadius: blurRadius,
                        onDetached: { selection = nil }
                    )
                }
        }
    }
}

private struct GallerySheetPresentationModifier: ViewModifier {
    let gid: String
    let blurRadius: Double
    let onDetached: () -> Void

    @State private var detachmentToken = UUID()

    func body(content: Content) -> some View {
        content
            .autoBlur(radius: blurRadius)
            .environment(\.inSheet, true)
            .presentationDragIndicator(.visible)
            .overlay(alignment: .top) {
                GallerySheetDetachmentSource(
                    gid: gid,
                    detachmentToken: detachmentToken
                )
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: GallerySceneActivity.didDetachSceneNotification
                )
            ) { notification in
                guard notification.object as? UUID == detachmentToken else { return }
                onDetached()
            }
    }
}

private struct GallerySheetDetachmentSource: View {
    let gid: String
    let detachmentToken: UUID

    var body: some View {
        Color.clear
            .frame(width: 96, height: 28)
            .contentShape(.interaction, Rectangle())
            .onDrag {
                GallerySceneActivity.itemProvider(
                    gid: gid,
                    url: nil,
                    detachmentToken: detachmentToken
                )
            } preview: {
                Capsule()
                    .fill(.secondary)
                    .frame(width: 36, height: 5)
                    .padding(12)
            }
            .accessibilityHidden(true)
    }
}

struct PlainLinearProgressViewStyle: ProgressViewStyle {
    func makeBody(configuration: ProgressViewStyleConfiguration) -> some View {
        ProgressView(value: CGFloat(configuration.fractionCompleted ?? 0), total: 1)
    }
}
extension ProgressViewStyle where Self == PlainLinearProgressViewStyle {
    static var plainLinear: PlainLinearProgressViewStyle {
        PlainLinearProgressViewStyle()
    }
}

// MARK: Image Modifier
struct CornersModifier: ImageModifier {
    let radius: CGFloat?

    init(radius: CGFloat? = nil) {
        self.radius = radius
    }

    func modify(_ image: KFCrossPlatformImage) -> KFCrossPlatformImage {
        if let radius = radius {
            return image.withRoundedCorners(radius: radius) ?? image
        } else {
            return image
        }
    }
}

struct OffsetModifier: ImageModifier {
    private let size: CGSize?
    private let offset: CGSize?

    init(size: CGSize?, offset: CGSize?) {
        self.size = size
        self.offset = offset
    }

    func modify(_ image: KFCrossPlatformImage) -> KFCrossPlatformImage {
        guard let size = size, let offset = offset
        else { return image }

        return image.cropping(size: size, offset: offset) ?? image
    }
}

struct RoundedOffsetModifier: ImageModifier {
    private let size: CGSize?
    private let offset: CGSize?

    init(size: CGSize?, offset: CGSize?) {
        self.size = size
        self.offset = offset
    }

    func modify(_ image: KFCrossPlatformImage) -> KFCrossPlatformImage {
        guard let size = size, let offset = offset,
              let croppedImg = image.cropping(size: size, offset: offset),
              let roundedCroppedImg = croppedImg.withRoundedCorners(radius: 5)
        else { return image.withRoundedCorners(radius: 5) ?? image }

        return roundedCroppedImg
    }
}

struct WebtoonModifier: ImageModifier {
    private let minAspect: CGFloat
    private let idealAspect: CGFloat

    init(minAspect: CGFloat, idealAspect: CGFloat) {
        self.minAspect = minAspect
        self.idealAspect = idealAspect
    }

    func modify(_ image: KFCrossPlatformImage) -> KFCrossPlatformImage {
        let width = image.size.width
        let height = image.size.height
        let idealHeight = width / idealAspect
        guard width / height < minAspect else { return image }
        return image.cropping(size: CGSize(width: width, height: idealHeight), offset: .zero) ?? image
    }
}

extension KFImage {
    func defaultModifier(withRoundedCorners: Bool = true) -> KFImage {
        self
            .imageModifier(CornersModifier(
                radius: withRoundedCorners ? 5 : nil
            ))
            .fade(duration: 0.25)
            .resizable()
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(
                width: radius,
                height: radius
            )
        )
        return Path(path.cgPath)
    }
}

struct PreviewImageResource: Equatable {
    let originalURL: URL?
    let sourceURL: URL?
    let cropSize: CGSize?
    let cropOffset: CGSize?

    var aspectRatio: CGFloat {
        guard let cropSize, cropSize.width > 0, cropSize.height > 0 else {
            return Defaults.ImageSize.previewAspect
        }
        return cropSize.width / cropSize.height
    }

    func processor(targetPixelSize: CGSize) -> PreviewImageProcessor {
        .init(
            cropSize: cropSize,
            cropOffset: cropOffset,
            targetPixelSize: targetPixelSize
        )
    }
}

struct PreviewImageProcessor: ImageProcessor {
    let cropSize: CGSize?
    let cropOffset: CGSize?
    let targetPixelSize: CGSize

    var identifier: String {
        "app.ehpanda.preview-thumbnail.v1"
            + "-crop:\(String(describing: cropSize))"
            + "-offset:\(String(describing: cropOffset))"
            + "-target:\(targetPixelSize)"
    }

    func process(
        item: ImageProcessItem,
        options: KingfisherParsedOptionsInfo
    ) -> KFCrossPlatformImage? {
        guard let sourceImage = DefaultImageProcessor.default.process(
            item: item,
            options: options
        ) else { return nil }

        let croppedImage: KFCrossPlatformImage
        if cropSize != nil || cropOffset != nil {
            guard let cropSize, let cropOffset else { return nil }
            let requestedRect = CGRect(
                origin: .init(x: cropOffset.width, y: cropOffset.height),
                size: cropSize
            )
            let cropRect = requestedRect.intersection(
                CGRect(origin: .zero, size: sourceImage.size)
            )
            guard !cropRect.isNull, !cropRect.isEmpty,
                  let image = sourceImage.cropping(to: cropRect)
            else { return nil }
            croppedImage = image
        } else {
            croppedImage = sourceImage
        }

        guard targetPixelSize.width > 0, targetPixelSize.height > 0,
              croppedImage.size.width > 0, croppedImage.size.height > 0
        else { return croppedImage }

        let scale = min(
            1,
            min(
                targetPixelSize.width / croppedImage.size.width,
                targetPixelSize.height / croppedImage.size.height
            )
        )
        let outputSize = CGSize(
            width: max(1, floor(croppedImage.size.width * scale)),
            height: max(1, floor(croppedImage.size.height * scale))
        )

        // Redrawing detaches a sprite crop from the full backing bitmap.
        return croppedImage.kf.resize(to: outputSize)
    }
}

struct PreviewResolver {
    static func resolve(originalURL: URL?) -> PreviewImageResource {
        guard let url = originalURL,
              let (plainURL, size, offset) = Parser.parsePreviewConfigs(url: url)
        else {
            return .init(
                originalURL: originalURL,
                sourceURL: originalURL,
                cropSize: nil,
                cropOffset: nil
            )
        }
        return .init(
            originalURL: originalURL,
            sourceURL: plainURL,
            cropSize: size,
            cropOffset: offset
        )
    }

    static func getPreviewConfigs(originalURL: URL?) -> (URL?, ImageModifier) {
        let resource = resolve(originalURL: originalURL)
        return (
            resource.sourceURL,
            RoundedOffsetModifier(size: resource.cropSize, offset: resource.cropOffset)
        )
    }
}
