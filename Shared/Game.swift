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

	let id: UUID
	let rows: Int
	let columns: Int
	let mode: Mode
	private(set) var openTileId: Int?

	enum Mode: String, Codable, Equatable {
		case classic
		case swap
	}

	enum State: String, Codable {
		case new		// Tiles are off-screen at the bottom
		case playing	// Normal game-play state
		case finished	// Game is finished
		case fading
	}

	var moves: Int = 0
	var accumulatedTime: Double = 0
	var tiles: [Tile]
	var state: State

	@MainActor init(rows: Int, columns: Int, mode: Mode, imageIsLandscape: Bool) {
		self.id = UUID()
		self.rows = rows
		self.columns = columns
		self.mode = mode
		let totalTiles = rows * columns
		self.openTileId = Self.openTileIdentifier(
			totalTiles: totalTiles,
			columns: columns,
			mode: mode,
			imageIsLandscape: imageIsLandscape
		)
		self.tiles = (1...totalTiles).map { Tile(id: $0) }
		self.state = .new
	}

	@MainActor init(
		id: UUID,
		rows: Int,
		columns: Int,
		mode: Mode,
		openTileId: Int?,
		moves: Int,
		accumulatedTime: Double,
		tileIdentifiers: [Int],
		state: State
	) {
		self.id = id
		self.rows = rows
		self.columns = columns
		self.mode = mode
		self.openTileId = openTileId
		self.moves = moves
		self.accumulatedTime = accumulatedTime
		let restoredState: State = state == .fading ? .playing : state
		let renderState: Tile.RenderState = restoredState == .new ? .unset : .none
		self.tiles = tileIdentifiers.map { Tile(id: $0, renderState: renderState) }
		self.state = restoredState
	}

	private static func openTileIdentifier(
		totalTiles: Int,
		columns: Int,
		mode: Mode,
		imageIsLandscape: Bool
	) -> Int? {
		guard mode == .classic else { return nil }
		return imageIsLandscape ? totalTiles - columns + 1 : totalTiles
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

	func updateOpenTile(imageIsLandscape: Bool) {
		guard state == .new else { return }
		self.openTileId = Self.openTileIdentifier(
			totalTiles: rows * columns,
			columns: columns,
			mode: mode,
			imageIsLandscape: imageIsLandscape
		)
	}

	func startNewGame(imageIsLandscape: Bool) {
		self.state = .new
		updateOpenTile(imageIsLandscape: imageIsLandscape)
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
