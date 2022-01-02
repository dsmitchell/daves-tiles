//
//  PuzzleImages.swift
//  daves-tiles
//
//  Created by The App Studio LLC on 8/28/21.
//  Copyright © 2021 The App Studio LLC.
//

import UIKit

class PuzzleImages {

	static var currentImage: CGImage? = randomFavorite() {
		didSet { scaledImages.removeAll() }
	}

	private static var lastImageNumber = -1
	private static var scaledImages = [CGSize : CGImage]()

	static func imageMatching(size: CGSize) -> CGImage? {
		// TODO: Round the size to points so that we don't produce so many variations
		let roundedSize = CGSize(width: size.width.rounded(), height: size.height.rounded())
		if let scaledImage = scaledImages[roundedSize] { return scaledImage }
		print("Resizing image to \(roundedSize) (from \(size))")
		guard let image = currentImage else { return nil }
		let uiImage = UIImage(cgImage: image) // TODO: Get this to work with NSImage on mac as well (use CoreResolve probably)
		guard let resizedImage = uiImage.resized(toFill: roundedSize), let cgImage = resizedImage.cgImage else { return nil }
		scaledImages[roundedSize] = cgImage
		return cgImage
	}

	static func randomFavorite() -> CGImage {
		let formatter = NumberFormatter()
		formatter.positiveFormat = "00"
		formatter.formatWidth = 2
		var randomNumber = (01...14).randomElement()!
		while randomNumber == lastImageNumber {
			randomNumber = (01...14).randomElement()!
		}
		lastImageNumber = randomNumber
		let randomImageName = "Favorite" + formatter.string(from: randomNumber as NSNumber)!
		return UIImage(named: randomImageName)!.cgImage!
	}
}

fileprivate extension UIImage {

	func resized(toFill outputSize: CGSize) -> UIImage? {
		let scale = self.scale * max(outputSize.width / size.width, outputSize.height / size.height)
		let width = size.width * scale
		let height = size.height * scale
		let imageRect = CGRect(x: (outputSize.width - width) / 2.0, y: (outputSize.height - height) / 2.0, width: width, height: height)
		UIGraphicsBeginImageContextWithOptions(outputSize, true, 1)
		defer {
			UIGraphicsEndImageContext()
		}
		draw(in: imageRect)
		return UIGraphicsGetImageFromCurrentImageContext()
	}
}
