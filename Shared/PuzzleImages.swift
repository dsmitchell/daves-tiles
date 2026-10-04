//
//  PuzzleImages.swift
//  daves-tiles
//
//  Created by The App Studio LLC on 8/28/21.
//  Copyright © 2021 The App Studio LLC.
//

import SwiftUI

@MainActor enum PuzzleImageLibrary {

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
        let sources = (0...12).map(Source.bundled)
            + PuzzleImageStore.imageDirectories.map(Source.user)
        var source = sources.randomElement() ?? .bundled(1)
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
