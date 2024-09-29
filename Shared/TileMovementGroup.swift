//
//  TileMovementGroup.swift
//  daves-tiles
//
//  Created by The App Studio LLC on 7/20/21.
//  Copyright © 2021 The App Studio LLC.
//

import CoreGraphics
import SwiftUI

struct TileMovementGroup {

	enum MoveDirection {
		case up
		case down
		case left
		case right
		case drag
		case none
	}

	enum TrackingState {
		case initial
		case restarted
	}

	let tileIdentifiers: [Int]
	let direction: MoveDirection
	private(set) var lastPercentChange = 0.0
	private(set) var numberOfMidpointCrossings = 0
	private var movementFunction: (DragGesture.Value) -> (offset: CGVector, percentChange: CGFloat) = { _ in (.zero, 0) }
	var positionOffset = CGVector.zero
	private(set) var possibleTap = true
	private(set) var willMoveNext = true
	var trackingState: TrackingState? = .initial

	init(startingWith tileIndex: Int, in game: Game) {
		guard let openTile = game.tiles.firstIndex(where: { $0.id == game.openTileId }), openTile != tileIndex, tileIndex < game.tiles.count else {
			tileIdentifiers = [game.tiles[tileIndex].id]
			direction = .drag
			return
		}
		switch (game.gridIndex(for: openTile), game.gridIndex(for: tileIndex)) {
		case (let space, let tile) where space.column == tile.column && space.row < tile.row:
			tileIdentifiers = stride(from: openTile + game.columns, through: tileIndex, by: game.columns).map { game.tiles[$0].id }
			direction = .up
		case (let space, let tile) where space.column == tile.column && space.row > tile.row:
			tileIdentifiers = stride(from: tileIndex, to: openTile, by: game.columns).reversed().map { game.tiles[$0].id }
			direction = .down
		case (let space, let tile) where space.row == tile.row && space.column < tile.column:
			tileIdentifiers = (openTile+1...tileIndex).map { game.tiles[$0].id }
			direction = .left
		case (let space, let tile) where space.row == tile.row && space.column > tile.column:
			tileIdentifiers = (tileIndex..<openTile).reversed().map { game.tiles[$0].id }
			direction = .right
		default:
			tileIdentifiers = []
			direction = .none
		}
	}

	func indices(in game: Game) -> [Int] {
		return tileIdentifiers.compactMap { id in
			return game.tiles.firstIndex { $0.id == id }
		}
	}

	func isTracking(_ tile: Tile, in game: Game) -> Bool {
		guard let identifier = tileIdentifiers.last else { return false }
		return identifier == tile.id
	}

	mutating func applyDragGestureCrossedMidpoint(_ dragGesture: DragGesture.Value) -> Bool {
		let movement = movementFunction(dragGesture)
		defer {
			positionOffset = movement.offset
			lastPercentChange = movement.percentChange
		}
		if possibleTap, movement.offset.length > 10 {
			possibleTap = false
		}
		guard direction != .drag else { return false }
		if possibleTap || movement.percentChange >= 0.5 || lastPercentChange != 0.0 && movement.percentChange >= lastPercentChange {
			willMoveNext = true
		} else {
			willMoveNext = false
		}
		let crossedMidpoint = min(movement.percentChange, lastPercentChange) < 0.5 && max(movement.percentChange, lastPercentChange) >= 0.5
		if crossedMidpoint {
			numberOfMidpointCrossings += 1
		}
		// Return whether this move crossed the midpoint
		return crossedMidpoint
	}

	mutating func applyMovementFunction(for dragGesture: DragGesture.Value, with boardGeometry: BoardGeometry) {
		var lastOffset: CGVector = .zero
		var lastTranslation = dragGesture.translation
		switch direction.rotated(landscape: boardGeometry.isLandscape) {
		case .up:
			movementFunction = { dragGesture in
				defer {
					lastTranslation = dragGesture.translation
				}
				let bounded = (lastOffset.dy + dragGesture.translation.height - lastTranslation.height).bounded(by: -boardGeometry.tileSize.height...0)
				let percentChange = bounded / -boardGeometry.tileSize.height
				lastOffset = CGVector(dx: 0, dy: bounded)
				return (lastOffset, percentChange)
			}
		case .down:
			movementFunction = { dragGesture in
				defer {
					lastTranslation = dragGesture.translation
				}
				let bounded = (lastOffset.dy + dragGesture.translation.height - lastTranslation.height).bounded(by: 0...boardGeometry.tileSize.height)
				let percentChange = bounded / boardGeometry.tileSize.height
				lastOffset = CGVector(dx: 0, dy: bounded)
				return (lastOffset, percentChange)
			}
		case .left:
			movementFunction = { dragGesture in
				defer {
					lastTranslation = dragGesture.translation
				}
				let bounded = (lastOffset.dx + dragGesture.translation.width - lastTranslation.width).bounded(by: -boardGeometry.tileSize.width...0)
				let percentChange = bounded / -boardGeometry.tileSize.width
				lastOffset = CGVector(dx: bounded, dy: 0)
				return (lastOffset, percentChange)
			}
		case .right:
			movementFunction = { dragGesture in
				defer {
					lastTranslation = dragGesture.translation
				}
				let bounded = (lastOffset.dx + dragGesture.translation.width - lastTranslation.width).bounded(by: 0...boardGeometry.tileSize.width)
				let percentChange = bounded / boardGeometry.tileSize.width
				lastOffset = CGVector(dx: bounded, dy: 0)
				return (lastOffset, percentChange)
			}
		case .drag:
			movementFunction = { dragGesture in
				let vector = CGVector(fromDragGesture: dragGesture)
				return (vector, min(1.0, vector.length / boardGeometry.tileSize.width))
			}
		case .none:
			movementFunction = { _ in (.zero, 0) }
		}
	}
}

extension TileMovementGroup.MoveDirection {

	func rotated(landscape: Bool) -> Self {
		guard landscape else { return self }
		switch self {
		case .up: return .left
		case .down: return .right
		case .left: return .down
		case .right: return .up
		default: return self
		}
	}
}

fileprivate extension Comparable {

	func bounded(by limits: ClosedRange<Self>) -> Self {
		return min(max(self, limits.lowerBound), limits.upperBound)
	}
}

fileprivate extension CGVector {

	init(fromDragGesture gesture: DragGesture.Value) {
		self.init(dx: gesture.translation.width, dy: gesture.translation.height)
	}

	var length: CGFloat {
		sqrt(pow(dx, 2) + pow(dy, 2))
	}
}
