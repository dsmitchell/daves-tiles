//
//  PuzzleImageImport.swift
//  daves-tiles
//

import CoreTransferable
import Foundation
@preconcurrency import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ImportedPuzzleMedia: Transferable, Sendable {

    enum Kind: String, Codable, Sendable {
        case image
        case livePhoto
    }

    let url: URL
    let kind: Kind

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .livePhoto) { received in
            try copiedFile(from: received.file, kind: .livePhoto)
        }
        FileRepresentation(importedContentType: .image) { received in
            try copiedFile(from: received.file, kind: .image)
        }
    }

    static func copiedFile(from source: URL, kind: Kind) throws -> ImportedPuzzleMedia {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(source.pathExtension)
        try FileManager.default.copyItem(at: source, to: destination)
        return ImportedPuzzleMedia(url: destination, kind: kind)
    }
}

@MainActor enum PuzzleImageImporter {

    static func importItem(_ item: PhotosPickerItem) async throws -> ImportedPuzzleMedia {
        let isLivePhoto = item.supportedContentTypes.contains {
            $0.conforms(to: .livePhoto)
        }
        do {
            if let livePhoto = try await item.loadTransferable(type: PHLivePhoto.self) {
                return try await exportLivePhotoResources(from: livePhoto)
            }
        } catch {
            if isLivePhoto {
                throw error
            }
        }
        if isLivePhoto {
            throw CocoaError(.fileReadUnknown)
        }

        guard let image = try await item.loadTransferable(type: ImportedPuzzleMedia.self) else {
            throw CocoaError(.fileReadUnknown)
        }
        return image
    }

    private static func exportLivePhotoResources(
        from livePhoto: PHLivePhoto
    ) async throws -> ImportedPuzzleMedia {
        let resources = PHAssetResource.assetResources(for: livePhoto)
        guard let imageResource = resources.first(where: {
            $0.type == .photo || $0.type == .fullSizePhoto
        }), let movieResource = resources.first(where: {
            $0.type == .pairedVideo || $0.type == .fullSizePairedVideo
        }) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        do {
            let imageURL = resourceURL(named: "still", resource: imageResource, in: directory)
            let movieURL = resourceURL(named: "motion", resource: movieResource, in: directory)
            try await write(imageResource, to: imageURL)
            try await write(movieResource, to: movieURL)
            return ImportedPuzzleMedia(url: directory, kind: .livePhoto)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func write(_ resource: PHAssetResource, to url: URL) async throws {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().writeData(
                for: resource,
                toFile: url,
                options: options
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func resourceURL(
        named name: String,
        resource: PHAssetResource,
        in directory: URL
    ) -> URL {
        let pathExtension = (resource.originalFilename as NSString).pathExtension
        return directory
            .appendingPathComponent(name)
            .appendingPathExtension(pathExtension)
    }
}
