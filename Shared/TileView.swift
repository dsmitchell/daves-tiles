//
//  TileView.swift
//  davestiles
//
//  Created by The App Studio LLC on 7/3/21.
//

import SwiftUI

struct Tile: Identifiable {
	
	let id: Int
	var isActive: Bool = false
	var isSelected: Bool = false
	var isTracking: Bool = false
	let isOpen: Bool
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
			if let image = image {
				if roundedBorder {
					image
						.resizable()
						.overlay(roundedRectangle.stroke(Color.white, lineWidth: roundedBorder ? 4 : 0))
						.clipShape(roundedRectangle)
						.padding(roundedBorder ? 1 : 0)
				} else {
					image
						.resizable()
				}
			} else {
				roundedRectangle
					.foregroundColor(Color(hue: Double(tile.id) / 24.0, saturation: 1, brightness: 1))
					.overlay(roundedRectangle.stroke(Color.white, lineWidth: roundedBorder ? 4 : 0))
					.padding(roundedBorder ? 2 : 0)
			}
			if tile.isOpen {
				Image(systemName: "star.fill")
					.font(.title)
					.foregroundColor(.white)
					.shadow(color: .black, radius: 2)
			} else {
				Text("\(tile.id)")
					.font(.title)
					.foregroundColor(.white)
					.shadow(color: .black, radius: 2)
			}
		}
		.scaleEffect(tile.isSelected ? 1.15 : 1.0)
	}
}

struct TileView_Previews: PreviewProvider {
    static var previews: some View {
		let image = Image("PuzzleImage")
		VStack(spacing: 0) {
			TileView(tile: Tile(id: 5, isActive: true, isSelected: false, isTracking: true, isOpen: false), image: image, isMatched: false)
				.frame(width: 160, height: 160)
			TileView(tile: Tile(id: 4, isOpen: false), image: image, isMatched: true)
				.frame(width: 160, height: 160)
		}
    }
}
