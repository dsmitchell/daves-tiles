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
		case .rounded(let radius):
			return RoundedRectangle(cornerRadius: radius).path(in: rect)
		case .rectangle:
			return Rectangle().path(in: rect)
		}
	}
}

struct TileView<Background: View>: View {

	let id: Int
	let isSelected: Bool
	let isMatched: Bool
	let tileSize: CGSize
	let drawsBorder: Bool
	let showNumber: Bool
	let text: String?
	let background: Background

	init(
		id: Int,
		isSelected: Bool,
		isMatched: Bool,
		tileSize: CGSize,
		drawsBorder: Bool,
		showNumber: Bool,
		text: String?,
		@ViewBuilder background: () -> Background
	) {
		self.id = id
		self.isSelected = isSelected
		self.isMatched = isMatched
		self.tileSize = tileSize
		self.drawsBorder = drawsBorder
		self.showNumber = showNumber
		self.text = text
		self.background = background()
	}

	var body: some View {
		let roundedBorder = isSelected || !isMatched
		let roundedRadius = roundedBorder ? 8.0 : 0.0
		let roundedRectangle = RoundedRectangle(cornerRadius: roundedRadius)

		ZStack {
			background
				.mask(
					RoundedRectangle(cornerRadius: roundedRadius)
						.inset(by: roundedBorder ? 1 : 0)
				)
				.overlay(roundedRectangle.stroke(Color.primary, lineWidth: drawsBorder && isSelected ? 4 : 0))
				.clipShape(roundedBorder ? ImageClipShape.rounded(radius: roundedRadius) : ImageClipShape.rectangle)
			if showNumber {
				TileLabel(text: text, id: id, tileSize: tileSize)
			}
		}
#if os(visionOS)
		.contentShape(.interaction, .rect(cornerRadius: roundedRadius))
		.contentShape(.hoverEffect, .rect(cornerRadius: roundedRadius))
#else
		.contentShape(.rect(cornerRadius: roundedRadius))
		.scaleEffect(isSelected ? 1.15 : 1)
#endif
	}
}

struct TileLabel: View {

	let text: String?
	let id: Int
	let tileSize: CGSize?

	var body: some View {
		Group {
			if let text {
				Text(text)
			} else {
				Image(systemName: "star.fill")
			}
		}
		.font(tileSize.map { .system(size: max(8, min($0.width, $0.height) * 0.32)) } ?? .title)
		.foregroundColor(.white)
		.padding(2)
		.shadow(color: .black, radius: 2)
		.drawingGroup()
		.id("Label.\(id)")
#if os(visionOS)
		.offset(z: 6)
#endif
	}
}

#Preview {
	TileView(id: 5, isSelected: false, isMatched: false, tileSize: CGSize(width: 100, height: 100), drawsBorder: true, showNumber: true, text: "5") {
		Image("Favorite07")
			.resizable()
	}
}
