//
//  BoardRendering.swift
//  davestiles
//
//  Created by The App Studio LLC on 7/3/21.
//

import SwiftUI

struct BoardRendering {

	private(set) var arrangedIndices: [Int]
	/*@ObservedObject*/ private(set) var game: Game
	private enum Tracking {
		case notTracking
		case tracking(willMoveNext: Bool)
	}
	private var trackingState: Tracking = .notTracking
	private var possibleTouch = false

	private(set) var positionOffset = CGVector.zero
	private(set) var lastPercentChange: CGFloat = 0.0

	private var movementFunction: (DragGesture.Value) -> (offset: CGVector, percentChange: CGFloat)
	var movementGroup: Game.TileMovementGroup?

	init(game: Game) {
		self.arrangedIndices = Array(0..<game.tiles.count)
		self.movementFunction = { _ in (.zero, 0) }
		self.game = game
	}
}

extension BoardRendering {

	typealias BoardGeometry = (boardSize: CGSize, tileSize: CGSize, positions: [CGPoint])
	typealias TileRenderingInfo = (tile: Tile, image: Image?, position: CGPoint, isMatched: Bool)
	typealias TileLabelRenderingInfo = (tile: Tile, index: Int, position: CGPoint)

	var tracking: Bool {
		return game.tiles.contains { $0.isTracking }
//		switch trackingState {
//		case .notTracking: return false
//		default: return true
//		}
	}

	func position(for tileIndex: Int, in game: Game, with length: CGFloat, rotated: Bool) -> CGPoint {
		let gridIndex = game.gridIndex(for: tileIndex)
		let column = rotated ? gridIndex.row : gridIndex.column
		let row = rotated ? game.columns - gridIndex.column - 1 : gridIndex.row
		return CGPoint(x: (CGFloat(column) + 0.5) * length, y: (CGFloat(row) + 0.5) * length)
	}

	func boardGeometry(from geometryProxy: GeometryProxy) -> BoardGeometry {
		let rotated = geometryProxy.size.width > geometryProxy.size.height
		let columns = rotated ? game.rows : game.columns
		let rows = rotated ? game.columns : game.rows
		let length = min(geometryProxy.size.width / CGFloat(columns), geometryProxy.size.height / CGFloat(rows))
		let range = (0...game.tiles.count)
		let boardSize = CGSize(width: length * CGFloat(columns), height: length * CGFloat(rows))
		let offset = CGVector(dx: (geometryProxy.size.width - boardSize.width) / 2,
							  dy: (geometryProxy.size.height - boardSize.height) / 2)
		return (boardSize, CGSize(width: length, height: length), range.map {
			position(for: $0, in: game, with: length, rotated: rotated) + offset
		})
	}

	func arrangedLabels(with locations: BoardGeometry) -> [TileLabelRenderingInfo] {
		return arrangedIndices.map { index in
			// TODO: Consider declaring the "open tile" as the position with the greated row & col value
			let tile = game.tiles[index]
			let position = locations.positions[index]
			return (tile, index, position)
		}
	}

	func arrangedTiles(with locations: BoardGeometry) -> [TileRenderingInfo] {
		return arrangedLabels(with: locations).map { tile, index, position in
			guard locations.boardSize != .zero, let image = game.imageMatching(size: locations.boardSize) else {
				return (tile, nil, position, game.isMatched(tile: tile, index: index))
			}
			let tilePosition = tile.id - 1
			let rotated = locations.boardSize.width > locations.boardSize.height
			let gridIndex = (row: tilePosition / game.columns, column: tilePosition % game.columns)
			let column = rotated ? gridIndex.row : gridIndex.column
			let row = rotated ? game.columns - gridIndex.column - 1 : gridIndex.row
			let origin = CGPoint(x: CGFloat(column) * locations.tileSize.width, y: CGFloat(row) * locations.tileSize.height)
			let frame = CGRect(origin: origin, size: locations.tileSize)
			let cgImage = image.cropping(to: frame)
			let swImage = Image.init(decorative: cgImage!, scale: 1)
			return (tile, swImage, position, game.isMatched(tile: tile, index: index))
		}
	}

	mutating func throwTile(at index: Int) {
		game.tiles[index].isMoving = true
		guard let indexToRemove = arrangedIndices.firstIndex(of: index) else { return }
		arrangedIndices.remove(at: indexToRemove)
		arrangedIndices.append(index)
	}

	mutating func stopThrowingTiles() {
		for index in 0..<game.tiles.count {
			game.tiles[index].isMoving = false
		}
	}

	func tileIndex(from point: CGPoint, with locations: BoardGeometry) -> Int? {
		let frames = locations.positions.map { position -> CGRect in
			let origin = CGPoint(x: position.x - locations.tileSize.width / 2, y: position.y - locations.tileSize.height / 2)
			return CGRect(origin: origin, size: locations.tileSize)
		}
		guard let tileIndex = frames.firstIndex(where: { $0.contains(point) }) else {
			return nil
		}
		return tileIndex
	}

	mutating func continueTracking(dragGesture: DragGesture.Value) {
		guard case .tracking = trackingState else { return }
		let result = movementFunction(dragGesture)
//		print(" - tracking \(result.offset.length)")
		if let movementGroup = movementGroup {
			for index in movementGroup.indices {
				game.tiles[index].isMoving = true
			}
		}
		if possibleTouch, result.offset.length > 10 {
			possibleTouch = false
		}
		if possibleTouch || result.percentChange >= 0.5 || result.percentChange >= lastPercentChange && lastPercentChange != 0.0 {
			trackingState = .tracking(willMoveNext: true)
		} else {
			trackingState = .tracking(willMoveNext: false)
		}
		// TODO: transition of result.percentChange crossing the 0.5 threshold should trigger a sound
		if min(result.percentChange, lastPercentChange) < 0.5, max(result.percentChange, lastPercentChange) >= 0.5 {
			SoundEffects.default.play(.slide)
		}
		lastPercentChange = result.percentChange
		positionOffset = result.offset
	}

	mutating func randomMove() -> Tile {
		let indices = movementGroup?.indices
		stopTracking(forceCancel: true)
		let movedTile = game.randomMove(except: indices)
		game.tiles[movedTile.to].isSelected = true
		guard let arrangedIndex = arrangedIndices.firstIndex(of: movedTile.from) else { fatalError("Logic error updating arrangedIndices") }
		var newIndices = arrangedIndices
		newIndices.remove(at: arrangedIndex)
		// Random Move shifts the indices of the tiles in between. Shift based on direction
		for index in 0..<newIndices.count {
			let tileIndex = newIndices[index]
			if movedTile.from < movedTile.to {
				guard (movedTile.from+1...movedTile.to).contains(tileIndex) else { continue }
				newIndices[index] = tileIndex - 1
			} else {
				guard (movedTile.to..<movedTile.from).contains(tileIndex) else { continue }
				newIndices[index] = tileIndex + 1
			}
		}
		newIndices.append(movedTile.to)
		arrangedIndices = newIndices
		return game.tiles[movedTile.to]
	}

	mutating func completeRandomMove(_ movedTile: Tile) {
		guard let index = game.tiles.firstIndex(where: { $0.id == movedTile.id }) else { return }
		game.tiles[index].isSelected = false
		arrangedIndices.swapAt(0, 1) // This should be a safe change to the indices that doesn't impact the final rendering
	}

	mutating func startNewGame() {
		game.startNewGame()
		arrangedIndices = game.tiles.map { $0.id - 1 } // Assigning this makes the animation happen
	}

	mutating func startTracking(movementGroup: Game.TileMovementGroup, from dragGesture: DragGesture.Value, with locations: BoardGeometry) {
//		guard case .notTracking = trackingState else { fatalError("Returning early") }
//		let touchedTileIndex = movementGroup.indices.last!
//		print("Tracking tile \(game.tiles[touchedTileIndex].id) @ \(touchedTileIndex+1)")
		trackingState = .tracking(willMoveNext: true)
		lastPercentChange = 0
		positionOffset = .zero
		possibleTouch = true
		self.movementGroup = movementGroup
		var lastOffset: CGVector = .zero
		var lastTranslation = dragGesture.translation
		switch movementGroup.direction.rotated(locations.boardSize.width > locations.boardSize.height) {
		case .up:
			movementFunction = { dragGesture in
				defer {
					lastTranslation = dragGesture.translation
				}
				let bounded = (lastOffset.dy + dragGesture.translation.height - lastTranslation.height).bounded(by: -locations.tileSize.height...0)
				let percentChange = bounded / -locations.tileSize.height
				lastOffset = CGVector(dx: 0, dy: bounded)
				return (lastOffset, percentChange)
			}
		case .down:
			movementFunction = { dragGesture in
				defer {
					lastTranslation = dragGesture.translation
				}
				let bounded = (lastOffset.dy + dragGesture.translation.height - lastTranslation.height).bounded(by: 0...locations.tileSize.height)
				let percentChange = bounded / locations.tileSize.height
				lastOffset = CGVector(dx: 0, dy: bounded)
				return (lastOffset, percentChange)
			}
		case .left:
			movementFunction = { dragGesture in
				defer {
					lastTranslation = dragGesture.translation
				}
				let bounded = (lastOffset.dx + dragGesture.translation.width - lastTranslation.width).bounded(by: -locations.tileSize.width...0)
				let percentChange = bounded / -locations.tileSize.width
				lastOffset = CGVector(dx: bounded, dy: 0)
				return (lastOffset, percentChange)
			}
		case .right:
			movementFunction = { dragGesture in
				defer {
					lastTranslation = dragGesture.translation
				}
				let bounded = (lastOffset.dx + dragGesture.translation.width - lastTranslation.width).bounded(by: 0...locations.tileSize.width)
				let percentChange = bounded / locations.tileSize.width
				lastOffset = CGVector(dx: bounded, dy: 0)
				return (lastOffset, percentChange)
			}
		default:
			movementFunction = { dragGesture in (CGVector(fromDragGesture: dragGesture), 0) }
		}
		// TODO: Try to find an efficient/clean way to use .move(fromOffsets:toOffset:)
		arrangedIndices.removeAll(where: movementGroup.indices.contains)
		arrangedIndices = arrangedIndices + movementGroup.indices
		game.selectTiles(with: movementGroup.indices)
	}

	mutating func stopTracking(forceCancel: Bool = false) {
		guard let movementGroup = movementGroup else { return }
		guard case .tracking(let willMoveNext) = trackingState else {
			if forceCancel {
				game.cancelMove(with: movementGroup)
				for index in movementGroup.indices {
					game.tiles[index].isSelected = false
				}
				positionOffset = .zero
				self.movementGroup = nil
				trackingState = .notTracking
			}
			return /*fatalError("This is a surprise)")*/
		}
		if possibleTouch && !forceCancel {
			SoundEffects.default.play(.slide)
		}
		if willMoveNext && !forceCancel {
			game.completeMove(with: movementGroup)
			for index in movementGroup.indices {
				let nextIndex: Int
				switch movementGroup.direction {
				case .up: nextIndex = index-game.columns
				case .down: nextIndex = index+game.columns
				case .left: nextIndex = index-1
				case .right: nextIndex = index+1
				case .drag: nextIndex = index // TODO: .drag will need to know the drop destination, so that we can remove and append appropriately
				}
				guard let arrangedIndex = arrangedIndices.firstIndex(of: nextIndex) else { fatalError("Logic error calculating arrangedIndices") }
				arrangedIndices.remove(at: arrangedIndex)
				arrangedIndices.append(nextIndex)
			}
		} else {
			game.cancelMove(with: movementGroup)
			if forceCancel {
				for index in movementGroup.indices {
					game.tiles[index].isSelected = false
				}
			} else {
				arrangedIndices.swapAt(0, 1) // This should be a safe change to the indices that doesn't impact the final rendering
			}
		}
		positionOffset = .zero
//		lastPercentChange = 0.0
		self.movementGroup = nil
		trackingState = .notTracking
	}

	// TODO: This function should have targeted indices
	mutating func deselectTiles() {
		for index in 0..<game.tiles.count {
			game.tiles[index].isSelected = false
			game.tiles[index].isTracking = false
		}
		arrangedIndices.swapAt(0, 1) // This should be a safe change to the indices that doesn't impact the final rendering
	}
}

extension Comparable {

	func bounded(by limits: ClosedRange<Self>) -> Self {
		return min(max(self, limits.lowerBound), limits.upperBound)
	}
}

extension CGPoint {

	static func + (left: CGPoint, right: CGVector) -> CGPoint {
		return CGPoint(x: left.x + right.dx, y: left.y + right.dy)
	}
}

extension CGVector {

	init(fromDragGesture gesture: DragGesture.Value) {
		self.init(dx: gesture.translation.width, dy: gesture.translation.height)
	}

	var length: CGFloat {
		sqrt(pow(dx, 2) + pow(dy, 2))
	}
}

extension Game.MoveDirection {

	func rotated(_ rotated: Bool) -> Self {
		guard rotated else { return self }
		switch self {
		case .up: return .left
		case .down: return .right
		case .left: return .down
		case .right: return .up
		case .drag: return .drag
		}
	}
}
