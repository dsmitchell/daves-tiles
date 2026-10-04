//
//  PuzzleImage.swift
//  daves-tiles
//

import CoreGraphics
import SwiftUI

struct PuzzleImage: Equatable {

    struct LivePhotoResources: Equatable, Sendable {
        let stillImageURL: URL
        let movieURL: URL

        var allURLs: [URL] { [stillImageURL, movieURL] }
    }

    enum Content {
        case still(Image)
        case livePhoto(resources: LivePhotoResources, stillFrame: PuzzleImageStillFrame)
    }

    let id: String
    let content: Content
    let isLandscape: Bool

    @MainActor init(image: Image) {
        let renderer = ImageRenderer(content: image)
        var size = CGSize.zero
        renderer.render { renderedSize, _ in size = renderedSize }
        self.id = UUID().uuidString
        self.content = .still(image)
        self.isLandscape = size.width > size.height
    }

    init(id: String, content: Content, isLandscape: Bool) {
        self.id = id
        self.content = content
        self.isLandscape = isLandscape
    }

    @MainActor func image(toFill size: CGSize) -> Image {
        switch content {
        case .still(let image):
            image
        case .livePhoto(_, let stillFrame):
            stillFrame.image(toFill: size)
        }
    }

    var livePhotoMovieURL: URL? {
        guard case .livePhoto(let resources, _) = content else { return nil }
        return resources.movieURL
    }

    var livePhotoResourceURLs: [URL]? {
        guard case .livePhoto(let resources, _) = content else { return nil }
        return resources.allURLs
    }

    static func == (lhs: PuzzleImage, rhs: PuzzleImage) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor final class PuzzleImageStillFrame {

    let original: Image

    private let cgImage: CGImage
    private var resizedImages = [CGSize: Image]()

    init(cgImage: CGImage) {
        self.cgImage = cgImage
        self.original = Image(decorative: cgImage, scale: 1)
    }

    func image(toFill size: CGSize) -> Image {
        let roundedSize = CGSize(
            width: size.width.rounded(),
            height: size.height.rounded()
        )
        guard roundedSize.width > 0, roundedSize.height > 0 else { return original }
        if let image = resizedImages[roundedSize] {
            return image
        }
        guard let resized = cgImage.resized(toFill: roundedSize) else {
            return original
        }
        let image = Image(decorative: resized, scale: 1)
        resizedImages[roundedSize] = image
        return image
    }
}

extension EnvironmentValues {

    @Entry var puzzleImage: PuzzleImage?
    @Entry var puzzleImageIsPlaying = true
}

private extension CGImage {

    func resized(toFill outputSize: CGSize) -> CGImage? {
        let outputWidth = Int(outputSize.width.rounded(.up))
        let outputHeight = Int(outputSize.height.rounded(.up))
        guard outputWidth > 0, outputHeight > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: outputWidth,
            height: outputHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let sourceSize = CGSize(width: width, height: height)
        let scale = max(outputSize.width / sourceSize.width, outputSize.height / sourceSize.height)
        let scaledSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let imageRect = CGRect(
            x: (outputSize.width - scaledSize.width) / 2,
            y: (outputSize.height - scaledSize.height) / 2,
            width: scaledSize.width,
            height: scaledSize.height
        )

        context.interpolationQuality = .high
        context.draw(self, in: imageRect)
        return context.makeImage()
    }
}
