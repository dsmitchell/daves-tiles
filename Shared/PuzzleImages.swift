//
//  PuzzleImages.swift
//  daves-tiles
//
//  Created by The App Studio LLC on 8/28/21.
//  Copyright © 2021 The App Studio LLC.
//

import Foundation
import CoreGraphics
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

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
		guard let cgImage = image.resized(toFill: roundedSize) else { return nil }
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
#if canImport(AppKit)
		return NSImage(named: randomImageName)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
#elseif canImport(UIKit)
		return UIImage(named: randomImageName)!.cgImage!
#endif
	}
}

fileprivate extension CGImage {
	
	func resized(toFill outputSize: CGSize) -> CGImage? {

		guard let colorSpace = self.colorSpace else { return nil }

		let outputWidth = Int(outputSize.width)
		let outputHeight = Int(outputSize.height)

		let bytesPerPixel = self.bitsPerPixel / self.bitsPerComponent
		let destBytesPerRow = outputWidth * bytesPerPixel

		guard let context = CGContext(data: nil, width: outputWidth, height: outputHeight, bitsPerComponent: self.bitsPerComponent, bytesPerRow: destBytesPerRow, space: colorSpace, bitmapInfo: self.bitmapInfo.rawValue) else { return nil }

		let size = CGSize(width: self.width, height: self.height)
		let scale = max(outputSize.width / size.width, outputSize.height / size.height)
		let width = size.width * scale
		let height = size.height * scale
		let imageRect = CGRect(x: (outputSize.width - width) / 2.0, y: (outputSize.height - height) / 2.0, width: width, height: height)

		context.interpolationQuality = .high
		context.draw(self, in: imageRect)

		return context.makeImage()
	}
}
