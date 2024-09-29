//
//  Game.swift
//  daves-tiles
//
//  Created by The App Studio LLC on 7/6/21.
//  Copyright © 2021 The App Studio LLC.
//

import SwiftUI

fileprivate struct GameTemplate: TilesGame {
	let rows: Int
	let columns: Int
	var tiles: [Tile]
	let openTileId: Int?
}

@Observable class Game: Identifiable, TilesGame {

	let id = UUID()
	let rows: Int
	let columns: Int
	let openTileId: Int?

	enum Mode: Equatable {
		case classic
		case swap
	}

	enum State {
		case new		// Tiles are off-screen at the bottom
		case playing	// Normal game-play state
		case finished	// Game is finished
		case fading
	}

	var moves: Int = 0
	var accumulatedTime: Double = 0
	var tiles: [Tile]
	var state: State

	@MainActor init(rows: Int, columns: Int, mode: Mode) {
		self.rows = rows
		self.columns = columns
		let totalTiles = rows * columns
#if os(iOS)
		self.openTileId = mode == .classic ? totalTiles : nil
#elseif os(macOS) // These platforms are more likely to be landscape-centric
		self.openTileId = mode == .classic ? totalTiles - columns + 1 : nil
#else
		self.openTileId = mode == .classic ? PuzzleImages.imageIsLandscape ?? false ? totalTiles - columns + 1 : totalTiles : nil
#endif
		self.tiles = (1...totalTiles).map { Tile(id: $0) }
		self.state = .new
	}

	var isFinished: Bool {
		tiles.enumerated().allSatisfy { index, element in
			isMatched(tile: element, index: index)
		}
	}

	func applyRenderState(_ renderState: Tile.RenderState, to tileIdentifiers: [Int]) {
		for id in tileIdentifiers {
			guard let index = tiles.firstIndex(where: { $0.id == id }) else { continue }
			tiles[index].renderState = renderState
		}
	}

	func isMatched(tile: Tile, index: Int) -> Bool {
		return tile.id == index + 1
	}

	func startNewGame() {
		self.state = .new
		var template = GameTemplate(rows: rows, columns: columns, tiles: (1...rows * columns).map { Tile(id: $0) }, openTileId: openTileId)
		repeat {
			template.randomMove()
		} while template.tiles.enumerated().contains { index, tile in
			isMatched(tile: tile, index: index)
		}
		self.accumulatedTime = 0
		self.moves = 0
		self.tiles = template.tiles
	}
}
