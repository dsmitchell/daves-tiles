//
//  Tile.swift
//  daves-tiles
//
//  Created by The App Studio LLC on 2/11/24.
//  Copyright © 2024 The App Studio LLC.
//

import SwiftUI

struct Tile: Identifiable, Equatable, Hashable {

	enum RenderState: Equatable {
		case none
		case dragged
		case fading(wasFalling: Bool)
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

	static func == (lhs: Self, rhs: Self) -> Bool {
		return lhs.id == rhs.id
	}

	func hash(into hasher: inout Hasher) {
		hasher.combine(id)
	}
}
