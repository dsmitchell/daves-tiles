//
//  Tile.swift
//  daves-tiles
//
//  Created by The App Studio LLC on 2/11/24.
//  Copyright © 2024 The App Studio LLC.
//

import SwiftUI

struct Tile: Identifiable {

	enum RenderState: Equatable {
		case none
		case dragged
		case falling
		case released(percent: Double)
		case thrown
		case transitioning(toSelected: Bool)
		case unset
	}
	
	let id: Int
	var renderState: RenderState = .unset // This is for new game scenario

	var isSelected: Bool {
		switch renderState {
		case .none: return false
		case .dragged: return true
		case .released: return true
		case .thrown: return false
		case .transitioning(let selected): return selected
		default: return false
		}
	}
}

extension Tile: Hashable {

	static func == (lhs: Self, rhs: Self) -> Bool {
		// .renderState is needed in order to ensure redraws occur
		return lhs.id == rhs.id && lhs.renderState == rhs.renderState
	}

	func hash(into hasher: inout Hasher) {
		hasher.combine(id) // .renderState is not needed for Hashable
	}
}
