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

	let tile: Tile
	let image: Image?
	let imageBounds: CGRect = .zero
	let isMatched: Bool
	let showNumber: Bool
	let text: String?

	var body: some View {
		let selected = tile.isSelected
		let roundedBorder = selected || !isMatched
		let roundedRadius = roundedBorder ? 8.0 : 0.0
		ZStack {
			let roundedRectangle = RoundedRectangle(cornerRadius: roundedRadius)
			background(for: tile.id, in: roundedRectangle)
				.overlay(roundedRectangle.stroke(Color.primary, lineWidth: selected ? 4 : 0))
				.clipShape(roundedBorder ? ImageClipShape.rounded(radius: roundedRadius) : ImageClipShape.rectangle)
				.padding(roundedBorder ? 1 : 0)
			if showNumber {
				TileView.styledLabel(with: text)
			}
		}
#if os(visionOS)
		.contentShape(.hoverEffect, .rect(cornerRadius: roundedRadius))
#else
		.scaleEffect(selected ? 1.15 : 1.0)
#endif
	}

	@ViewBuilder
	func background(for id: Int, in roundedRectangle: RoundedRectangle) -> some View {
		if let image = image {
			image.resizable()
		} else {
			roundedRectangle.foregroundColor(Color(hue: Double(id) / 24.0, saturation: 1, brightness: 1))
		}
	}

	@ViewBuilder
	public static func styledLabel(with text: String?) -> some View {
		label(with: text)
			.id("label.\(text ?? "star")") // There will only ever be one tile with a nil text
			.font(.title)
			.foregroundColor(.white)
			.padding(2)
			.shadow(color: .black, radius: 2)
			.drawingGroup()
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
	let tile = Tile(id: 5, renderState: .none)
	
	return TileView(tile: tile, image: nil, isMatched: false, showNumber: true, text: "5")
		.frame(width: 160, height: 160)
}
