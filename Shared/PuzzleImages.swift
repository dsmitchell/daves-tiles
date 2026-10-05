//
//  PuzzleImages.swift
//  daves-tiles
//
//  Created by The App Studio LLC on 8/28/21.
//  Copyright © 2021 The App Studio LLC.
//

import SwiftUI

@MainActor enum PuzzleImageLibrary {

    static let bundledImageIDs = (0...11).map {
        String(format: "Favorite%02d", $0)
    }

    private static let disabledBundledImageIDsKey = "DisabledBundledPuzzleImageIDs"

    private enum Source: Equatable {
        case bundled(Int)
        case user(URL)
    }

    private static var lastSource: Source?

    static func initialFavorite() -> PuzzleImage {
        lastSource = .bundled(0)
        return bundledImage(0)
    }

    static func randomFavorite() -> PuzzleImage {
        let sources = (0...11).filter { isBundledImageEnabled(number: $0) }.map(Source.bundled)
            + PuzzleImageStore.imageDirectories.map(Source.user)
        var source = sources.randomElement() ?? .bundled(0)
        if sources.count > 1 {
            while source == lastSource {
                source = sources.randomElement()!
            }
        }
        lastSource = source

        switch source {
        case .bundled(let number):
            return bundledImage(number)
        case .user(let directory):
            return (try? PuzzleImageStore.puzzleImage(in: directory))
                ?? bundledImage(1)
        }
    }

    static func addUserMedia(_ imported: ImportedPuzzleMedia) async throws -> PuzzleImage {
        let image = try await PuzzleImageStore.add(imported)
        if let directory = PuzzleImageStore.imageDirectories.first(where: {
            $0.lastPathComponent == image.id
        }) {
            lastSource = .user(directory)
        }
        return image
    }

    static func bundledImages() -> [PuzzleImage] {
        bundledImageIDs.indices.map(bundledImage)
    }

    static func bundledImageName(id: String) -> LocalizedStringResource {
        switch id {
        case "Favorite00": "Moon Yawning"
        case "Favorite01": "Cherry Hill"
        case "Favorite02": "West Side Bench"
        case "Favorite03": "Rockefeller Center"
        case "Favorite04": "Bryant Park"
        case "Favorite05": "Maine Monument"
        case "Favorite06": "NYPL Tulips"
        case "Favorite07": "Noguchi's Cube"
        case "Favorite08": "Battery Park"
        case "Favorite09": "Columbus Circle"
        case "Favorite10": "Central Park"
        case "Favorite11": "Financial District"
        default: "Built-in Photo"
        }
    }

    static func userImages() -> [PuzzleImage] {
        PuzzleImageStore.imageDirectories.compactMap { try? PuzzleImageStore.puzzleImage(in: $0) }
    }

    static func image(id: String) -> PuzzleImage? {
        if let index = bundledImageIDs.firstIndex(of: id) {
            return bundledImage(index)
        }
        guard let directory = PuzzleImageStore.imageDirectories.first(where: {
            $0.lastPathComponent == id
        }) else { return nil }
        return try? PuzzleImageStore.puzzleImage(in: directory)
    }

    static func isBundledImageEnabled(id: String) -> Bool {
        !disabledBundledImageIDs.contains(id)
    }

    static func setBundledImage(_ id: String, enabled: Bool) {
        var disabledIDs = disabledBundledImageIDs
        if enabled {
            disabledIDs.remove(id)
        } else {
            let enabledCount = bundledImageIDs.filter { !disabledIDs.contains($0) }.count
            guard enabledCount > 1 else { return }
            disabledIDs.insert(id)
        }
        UserDefaults.standard.set(Array(disabledIDs), forKey: disabledBundledImageIDsKey)
    }

    static func deleteUserImage(id: String) throws {
        guard let directory = PuzzleImageStore.imageDirectories.first(where: {
            $0.lastPathComponent == id
        }) else { return }
        try PuzzleImageStore.deleteImage(in: directory)
        if lastSource == .user(directory) {
            lastSource = nil
        }
    }

    private static var disabledBundledImageIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: disabledBundledImageIDsKey) ?? [])
    }

    private static func isBundledImageEnabled(number: Int) -> Bool {
        isBundledImageEnabled(id: bundledImageIDs[number])
    }

    private static func bundledImage(_ number: Int) -> PuzzleImage {
        if number == 0 {
            return bundledLivePhoto() ?? bundledImage(1)
        }
        let name = String(format: "Favorite%02d", number)
        let image = Image(name)
        let size = renderedSize(of: image)
        return PuzzleImage(
            id: name,
            content: .still(image),
            isLandscape: size.width > size.height
        )
    }

    private static func bundledLivePhoto() -> PuzzleImage? {
        guard let imageURL = Bundle.main.url(forResource: "Favorite00", withExtension: "heic"),
              let movieURL = Bundle.main.url(forResource: "Favorite00", withExtension: "mov"),
              let decoded = PuzzleImageStore.decodedImage(in: imageURL) else {
            return nil
        }
        return PuzzleImage(
            id: "Favorite00",
            content: .livePhoto(
                resources: PuzzleImage.LivePhotoResources(
                    stillImageURL: imageURL,
                    movieURL: movieURL
                ),
                stillFrame: decoded.stillFrame
            ),
            isLandscape: decoded.isLandscape
        )
    }

    private static func renderedSize(of image: Image) -> CGSize {
        let renderer = ImageRenderer(content: image)
        var size = CGSize.zero
        renderer.render { renderedSize, _ in size = renderedSize }
        return size
    }
}
