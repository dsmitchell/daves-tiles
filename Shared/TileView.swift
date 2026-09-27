//
//  TileView.swift
//  daves-tiles
//
//  Created by The App Studio LLC on 7/3/21.
//  Copyright © 2021 The App Studio LLC.
//

import SwiftUI

enum ImageClipShape: Shape {

	case rounded(radius: CGFloat)
	case rectangle

	func path(in rect: CGRect) -> Path {
		switch self {
			case .rounded(let radius): return RoundedRectangle(cornerRadius: radius).path(in: rect)
			case .rectangle: return Rectangle().path(in: rect)
		}
	}
}

struct TileView: View {

	@Environment(\.puzzleImage) private var puzzleImage

	let id: Int
	let isSelected: Bool
	let isMatched: Bool
	let showNumber: Bool
	let text: String?
	let containerSize: CGSize
	let tileRect: CGRect

	var body: some View {
		let roundedBorder = isSelected || !isMatched
		let roundedRadius = roundedBorder ? 8.0 : 0.0
		ZStack {
			let roundedRectangle = RoundedRectangle(cornerRadius: roundedRadius)
			background(for: id, in: roundedRectangle)
				.mask(
					RoundedRectangle(cornerRadius: roundedRadius)
						.inset(by: roundedBorder ? 1 : 0)
				)
			.overlay(roundedRectangle.stroke(Color.primary, lineWidth: isSelected ? 4 : 0))
			.clipShape(roundedBorder ? ImageClipShape.rounded(radius: roundedRadius) : ImageClipShape.rectangle)
			if showNumber {
				TileView.styledLabel(with: text, for: id, tileSize: tileRect.size)
			}
		}
#if os(visionOS)
		.contentShape(.hoverEffect, .rect(cornerRadius: roundedRadius))
#else
		.contentShape(.rect(cornerRadius: roundedRadius))
		.scaleEffect(isSelected ? 1.15 : 1)
#endif
	}

	@ViewBuilder
	func background(for id: Int, in roundedRectangle: RoundedRectangle) -> some View {
		if let image = puzzleImage?.image {
			image
				.resizable()
				.scaledToFill()
				.frame(width: containerSize.width.rounded(), height: containerSize.height.rounded())
				.clipped()
				.offset(x: -tileRect.minX, y: -tileRect.minY)
				.frame(width: tileRect.width, height: tileRect.height, alignment: .topLeading)
		} else {
			roundedRectangle.foregroundColor(Color(hue: Double(id) / 24.0, saturation: 1, brightness: 1))
		}
	}

	@ViewBuilder
	public static func styledLabel(with text: String?, for id: Int, tileSize: CGSize) -> some View {
		label(with: text)
			.font(.system(size: max(8, min(tileSize.width, tileSize.height) * 0.32)))
			.foregroundColor(.white)
			.padding(2)
			.shadow(color: .black, radius: 2)
			.drawingGroup()
			.id("Label.\(id)")
#if os(visionOS)
			.offset(z: 6.0)
#endif
	}

	@ViewBuilder
	static func label(with text: String?) -> some View {
		if let text = text {
			Text(text)
		} else {
			Image(systemName: "star.fill")
		}
	}
}

#Preview {
	return TileView(id: 5, isSelected: false, isMatched: false, showNumber: true, text: "5",
					containerSize: CGSize(width: 480, height: 600), tileRect: CGRect(x: 0, y: 0, width: 160, height: 160))
		.environment(\.puzzleImage, PuzzleImage(image: Image("Favorite07")))
}
