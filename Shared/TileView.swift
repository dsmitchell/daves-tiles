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

	let id: Int
	let image: Image?
	let isSelected: Bool
	let isMatched: Bool
	let showNumber: Bool
	let text: String?

	var body: some View {
		let roundedBorder = isSelected || !isMatched
		let roundedRadius = roundedBorder ? 8.0 : 0.0
		ZStack {
			let roundedRectangle = RoundedRectangle(cornerRadius: roundedRadius)
			background(for: id, in: roundedRectangle)
				.overlay(roundedRectangle.stroke(Color.primary, lineWidth: isSelected ? 4 : 0))
				.clipShape(roundedBorder ? ImageClipShape.rounded(radius: roundedRadius) : ImageClipShape.rectangle)
				.padding(roundedBorder ? 1 : 0)
			if showNumber {
				TileView.styledLabel(with: text, for: id)
			}
		}
#if os(visionOS)
		.contentShape(.hoverEffect, .rect(cornerRadius: roundedRadius))
#else
		.scaleEffect(isSelected ? 1.15 : 1)
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
	public static func styledLabel(with text: String?, for id: Int) -> some View {
		label(with: text)
			.font(.title)
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
	return TileView(id: 5, image: Image("Favorite07"), isSelected: false, isMatched: false, showNumber: true, text: "5")
}
