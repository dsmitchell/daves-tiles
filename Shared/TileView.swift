//
//  TileView.swift
//  davestiles
//
//  Created by The App Studio LLC on 7/3/21.
//

import SwiftUI

struct Tile: Identifiable, Equatable, Hashable {

	enum RenderState: Equatable {
		case none(selected: Bool)
		case dragged
		case fading
		case lifted(falling: Bool)
		case released(percent: Double)
		case thrown(selected: Bool)
		case unset
	}
	
	let id: Int
	var renderState: RenderState = .unset // This is for new game scenario

	var isSelected: Bool {
		switch renderState {
		case .none(let selected): return selected
		case .dragged: return true
		case .released: return true
		case .thrown(let selected): return selected
		default: return false
		}
	}

	static func == (lhs: Self, rhs: Self) -> Bool {
		return lhs.id == rhs.id
	}

	func hash(into hasher: inout Hasher) {
		hasher.combine(id)
	}
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
	let isOpen: Bool
	let showNumber: Bool
	let text: String?

	var body: some View {
		let roundedBorder = !isOpen && (tile.isSelected || !isMatched)
		ZStack {
			let roundedRectangle = RoundedRectangle(cornerRadius: roundedBorder ? 8 : 0)
			background(for: tile, in: roundedRectangle)
				.overlay(roundedRectangle.stroke(Color.primary, lineWidth: tile.isSelected ? 4 : 0))
				.clipShape(roundedBorder ? ImageClipShape.rounded : ImageClipShape.rectangle)
				.padding(roundedBorder ? 1 : 0)
			if showNumber {
				TileView.styledLabel(for: tile, with: text)
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
	public static func styledLabel(for tile: Tile, with text: String?) -> some View {
		label(for: tile, with: text)
			.id("label.\(tile.id)")
			.font(.title)
			.foregroundColor(.white)
			.shadow(color: .black, radius: 2)
	}

	@ViewBuilder
	static func label(for tile: Tile, with text: String?) -> some View {
		if let text = text {
			Text(text)
		} else {
			Image(systemName: "star.fill")
		}
	}
}

struct TileView_Previews: PreviewProvider {
    static var previews: some View {
		let image = Image("PuzzleImage")
		VStack(spacing: 0) {
			TileView(tile: Tile(id: 5), image: image, isMatched: false, isOpen: false, showNumber: true, text: "5")
				.frame(width: 160, height: 160)
			TileView(tile: Tile(id: 4), image: image, isMatched: true, isOpen: false, showNumber: true, text: nil)
				.frame(width: 160, height: 160)
		}
    }
}
