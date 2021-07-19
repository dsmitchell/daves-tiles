//
//  TileView.swift
//  davestiles
//
//  Created by The App Studio LLC on 7/3/21.
//

import SwiftUI

struct Tile: Identifiable {
	
	let id: Int
	var isMoving: Bool = false
	var isSelected: Bool = false
	var isTracking: Bool = false
	let isOpen: Bool
}

enum ImageClipShape: Shape {

	case rounded
	case rectangle

	func path(in rect: CGRect) -> Path {
		switch self {
			case .rounded: return RoundedRectangle(cornerRadius: 8).path(in: rect)
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

	var body: some View {
		let roundedBorder = !tile.isOpen && (tile.isSelected || !isMatched)
		ZStack {
			let roundedRectangle = RoundedRectangle(cornerRadius: roundedBorder ? 8 : 0)
			background(for: tile, in: roundedRectangle)
				.overlay(roundedRectangle.stroke(Color.primary, lineWidth: tile.isSelected ? 4 : 0))
				.clipShape(roundedBorder ? ImageClipShape.rounded : ImageClipShape.rectangle)
				.padding(roundedBorder ? 1 : 0)
			if showNumber {
				TileView.styledLabel(for: tile)
			}
		}
		.scaleEffect(tile.isSelected ? 1.15 : 1.0)
	}

	@ViewBuilder
	func background(for tile: Tile, in roundedRectangle: RoundedRectangle) -> some View {
		if let image = image {
			image.resizable()
		} else {
			roundedRectangle.foregroundColor(Color(hue: Double(tile.id) / 24.0, saturation: 1, brightness: 1))
		}
	}

	@ViewBuilder
	public static func styledLabel(for tile: Tile) -> some View {
		label(for: tile)
			.id(tile.id)
			.font(.title)
			.foregroundColor(.white)
			.shadow(color: .black, radius: 2)
	}

	@ViewBuilder
	static func label(for tile: Tile) -> some View {
		// TODO: We need a function that converts id to display number, which can be affected by rotation
		if tile.isOpen {
			Image(systemName: "star.fill")
		} else {
			Text("\(tile.id)") // TODO: We need a function that converts id to display number, which can be affected by rotation
		}
	}
}

struct TileView_Previews: PreviewProvider {
    static var previews: some View {
		let image = Image("PuzzleImage")
		VStack(spacing: 0) {
			TileView(tile: Tile(id: 5, isMoving: true, isSelected: false, isTracking: true, isOpen: false), image: image, isMatched: false, showNumber: true)
				.frame(width: 160, height: 160)
			TileView(tile: Tile(id: 4, isOpen: false), image: image, isMatched: true, showNumber: true)
				.frame(width: 160, height: 160)
		}
    }
}
