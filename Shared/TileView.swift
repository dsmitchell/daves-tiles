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

	var body: some View {
		let roundedBorder = !tile.isOpen && (tile.isSelected || !isMatched)
		ZStack {
			let roundedRectangle = RoundedRectangle(cornerRadius: roundedBorder ? 8 : 0)
			background(for: tile, in: roundedRectangle)
				.overlay(roundedRectangle.stroke(Color.white, lineWidth: roundedBorder ? 4 : 0))
				.clipShape(roundedBorder ? ImageClipShape.rounded : ImageClipShape.rectangle)
				.padding(roundedBorder ? 1 : 0)
			label(for: tile)
				.id(tile.id)
				.font(.title)
				.foregroundColor(.white)
				.shadow(color: .black, radius: 2)
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
	func label(for tile: Tile) -> some View {
		if tile.isOpen {
			Image(systemName: "star.fill")
		} else {
			Text("\(tile.id)")
		}
	}
}

struct TileView_Previews: PreviewProvider {
    static var previews: some View {
		let image = Image("PuzzleImage")
		VStack(spacing: 0) {
			TileView(tile: Tile(id: 5, isMoving: true, isSelected: false, isTracking: true, isOpen: false), image: image, isMatched: false)
				.frame(width: 160, height: 160)
			TileView(tile: Tile(id: 4, isOpen: false), image: image, isMatched: true)
				.frame(width: 160, height: 160)
		}
    }
}
