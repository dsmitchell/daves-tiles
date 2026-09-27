//
//  PuzzleImages.swift
//  daves-tiles
//
//  Created by The App Studio LLC on 8/28/21.
//  Copyright © 2021 The App Studio LLC.
//

import Foundation
import CoreGraphics
import SwiftUI

struct PuzzleImage: Equatable {

	let image: Image
	let isLandscape: Bool

	@MainActor init(image: Image) {
		self.image = image
		let renderer = ImageRenderer(content: image)
		var size = CGSize.zero

		renderer.render { renderedSize, _ in
			size = renderedSize
		}
		self.isLandscape = size.width > size.height
	}
}

extension EnvironmentValues {

	@Entry var puzzleImage: PuzzleImage?
}

@MainActor class PuzzleImages {

	private static var lastImageNumber = -1

	static func randomImageName() -> String {
		let formatter = NumberFormatter()
		formatter.positiveFormat = "00"
		formatter.formatWidth = 2
		var randomNumber = (01...14).randomElement()!
		while randomNumber == lastImageNumber {
			randomNumber = (01...14).randomElement()!
		}
		lastImageNumber = randomNumber
		return "Favorite" + formatter.string(from: randomNumber as NSNumber)!
	}

	static func randomFavorite() -> PuzzleImage {
		PuzzleImage(image: Image(randomImageName()))
	}
}
