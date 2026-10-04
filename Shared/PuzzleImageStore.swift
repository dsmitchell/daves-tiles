//
//  PuzzleImageStore.swift
//  daves-tiles
//

import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@MainActor enum PuzzleImageStore {

    private struct Metadata: Codable {
        let kind: ImportedPuzzleMedia.Kind
        let isLandscape: Bool
    }

    static var imageDirectories: [URL] {
        guard let directory = try? imagesDirectory() else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []).filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    static func add(_ imported: ImportedPuzzleMedia) async throws -> PuzzleImage {
        let directory = try await Task.detached(priority: .userInitiated) {
            try store(imported)
        }.value
        return try puzzleImage(in: directory)
    }

    nonisolated private static func store(_ imported: ImportedPuzzleMedia) throws -> URL {
        guard let isLandscape = decodedImageIsLandscape(in: imported.url) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let directory = try imagesDirectory()
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let assetURL = directory
                .appendingPathComponent("asset")
                .appendingPathExtension(imported.url.pathExtension)
            try FileManager.default.copyItem(at: imported.url, to: assetURL)
            if imported.kind == .livePhoto {
                _ = try livePhotoResources(in: assetURL)
            }
            let metadata = Metadata(kind: imported.kind, isLandscape: isLandscape)
            try JSONEncoder().encode(metadata).write(
                to: directory.appendingPathComponent("metadata.json"),
                options: .atomic
            )
            return directory
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    static func puzzleImage(in directory: URL) throws -> PuzzleImage {
        let metadataData = try Data(
            contentsOf: directory.appendingPathComponent("metadata.json")
        )
        let metadata = try JSONDecoder().decode(Metadata.self, from: metadataData)
        guard let assetURL = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).first(where: { $0.lastPathComponent != "metadata.json" }),
              let decoded = decodedImage(in: assetURL) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let content: PuzzleImage.Content
        switch metadata.kind {
        case .image:
            content = .still(decoded.stillFrame.original)
        case .livePhoto:
            content = .livePhoto(
                resources: try livePhotoResources(in: assetURL),
                stillFrame: decoded.stillFrame
            )
        }
        return PuzzleImage(
            id: directory.lastPathComponent,
            content: content,
            isLandscape: metadata.isLandscape
        )
    }

    nonisolated private static func imagesDirectory() throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appDirectory = Bundle.main.bundleIdentifier ?? "DavesTiles"
        let directory = applicationSupport
            .appendingPathComponent(appDirectory, isDirectory: true)
            .appendingPathComponent("Puzzle Images", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    nonisolated private static func livePhotoResources(in url: URL) throws -> PuzzleImage.LivePhotoResources {
        let resources = mediaResourceURLs(in: url)
        guard let imageURL = resources.first(where: {
            contentType(of: $0)?.conforms(to: .image) == true
        }), let movieURL = resources.first(where: {
            contentType(of: $0)?.conforms(to: .movie) == true
        }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return PuzzleImage.LivePhotoResources(stillImageURL: imageURL, movieURL: movieURL)
    }

    nonisolated private static func mediaResourceURLs(in url: URL) -> [URL] {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .contentTypeKey
        ]
        let values = try? url.resourceValues(forKeys: keys)
        guard values?.isDirectory == true else { return [url] }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys)
        ) else {
            return []
        }
        return enumerator.compactMap { item in
            guard let itemURL = item as? URL,
                  (try? itemURL.resourceValues(forKeys: keys).isRegularFile) == true else {
                return nil
            }
            return itemURL
        }
    }

    nonisolated private static func contentType(of url: URL) -> UTType? {
        if let contentType = try? url.resourceValues(
            forKeys: [.contentTypeKey]
        ).contentType {
            return contentType
        }
        return UTType(filenameExtension: url.pathExtension)
    }

    static func decodedImage(
        in url: URL
    ) -> (stillFrame: PuzzleImageStillFrame, isLandscape: Bool)? {
        for candidate in mediaResourceURLs(in: url) {
            guard contentType(of: candidate)?.conforms(to: .image) == true,
                  let source = CGImageSourceCreateWithURL(candidate as CFURL, nil),
                  let image = orientationCorrectedImage(from: source) else {
                continue
            }
            return (
                PuzzleImageStillFrame(cgImage: image),
                image.width > image.height
            )
        }
        return nil
    }

    nonisolated private static func decodedImageIsLandscape(in url: URL) -> Bool? {
        for candidate in mediaResourceURLs(in: url) {
            guard contentType(of: candidate)?.conforms(to: .image) == true,
                  let source = CGImageSourceCreateWithURL(candidate as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                    as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int else {
                continue
            }
            return width > height
        }
        return nil
    }

    private static func orientationCorrectedImage(
        from source: CGImageSource
    ) -> CGImage? {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
            as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 1
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 1
        let maximumDimension = max(width, height)

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumDimension
        ]
        return CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        )
    }
}
