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

	var tracking: Bool {
		return game.tiles.contains { $0.isTracking }
//		switch trackingState {
//		case .notTracking: return false
//		default: return true
//		}
	}

	func position(for tileIndex: Int, in game: Game, with length: CGFloat) -> CGPoint {
		let gridIndex = tileIndex == game.tiles.count ? game.openGridIndex : game.gridIndex(for: tileIndex)
		return CGPoint(x: (CGFloat(gridIndex.column) + 0.5) * length, y: (CGFloat(gridIndex.row) + 0.5) * length)
	}

	func boardGeometry(from geometryProxy: GeometryProxy) -> BoardGeometry {
		let length = min(geometryProxy.size.width / CGFloat(game.columns), geometryProxy.size.height / CGFloat(game.rows))
		let range = (0...game.tiles.count) // TODO: When a game is won, ensure that board.tiles.count includes the _open_ tile
		return (geometryProxy.size, CGSize(width: length, height: length), range.map { position(for: $0, in: game, with: length) })
	}

	func arrangedTiles(with locations: BoardGeometry) -> [TileRenderingInfo] {

		let tileInfoFor: (Int, Bool) -> TileRenderingInfo = { index, isOpen in
			let tile = isOpen ? Tile(id: game.tiles.count + 1, isOpen: true) : game.tiles[index]
			let position = isOpen ? locations.positions[game.tiles.count] : locations.positions[index]
			guard locations.boardSize != .zero, let image = game.imageMatching(size: locations.boardSize) else {
				return (tile, nil, position, game.isMatched(tile: tile, index: index))
			}
			let tilePosition = tile.id - 1
			let gridIndex = (row: tilePosition / game.columns, column: tilePosition % game.columns)
			let origin = CGPoint(x: CGFloat(gridIndex.column) * locations.tileSize.width, y: CGFloat(gridIndex.row) * locations.tileSize.height)
			let frame = CGRect(origin: origin, size: locations.tileSize)
			let cgImage = image.cropping(to: frame)
			let swImage = Image.init(decorative: cgImage!, scale: 1)
			return (tile, swImage, position, game.isMatched(tile: tile, index: index))
		}

		guard let openTile = game.openTile else {
			return arrangedIndices.map { tileInfoFor($0, false) }
		}
		return [tileInfoFor(openTile, true)] + arrangedIndices.map { tileInfoFor($0, false) }
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

	mutating func randomMove() {
		let indices = movementGroup?.indices
		stopTracking(forceCancel: true)
		let movedTile = game.randomMove(except: indices)
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
	}

	mutating func startNewGame() {
		SoundEffects.default.play(.newGame)
		game.startNewGame()
		arrangedIndices = game.tiles.map { $0.id - 1 } // Assigning this makes the animation happen
	}

	mutating func startTracking(movementGroup: Game.TileMovementGroup, from dragGesture: DragGesture.Value, with locations: BoardGeometry) {
//		guard case .notTracking = trackingState else { fatalError("Returning early") }
		let touchedTileIndex = movementGroup.indices.last!
		print("Tracking tile \(game.tiles[touchedTileIndex].id) @ \(touchedTileIndex+1)")
		trackingState = .tracking(willMoveNext: true)
		lastPercentChange = 0
		positionOffset = .zero
		possibleTouch = true
		self.movementGroup = movementGroup
		var lastOffset: CGVector = .zero
		var lastTranslation = dragGesture.translation
		switch movementGroup.direction {
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
			switch movementGroup.direction {
			case .up:
				var newArrangedIndices = arrangedIndices
				for index in movementGroup.indices {
					let nextIndex = index-game.columns+1
					guard let arrangedIndex = newArrangedIndices.firstIndex(of: nextIndex) else { fatalError("Logic error calculating arrangedIndices") }
					newArrangedIndices.remove(at: arrangedIndex)
					newArrangedIndices.append(nextIndex)
				}
				arrangedIndices = newArrangedIndices
			case .down:
				var newArrangedIndices = arrangedIndices
				for index in movementGroup.indices {
					let nextIndex = index+game.columns-1
					guard let arrangedIndex = newArrangedIndices.firstIndex(of: nextIndex) else { fatalError("Logic error calculating arrangedIndices") }
					newArrangedIndices.remove(at: arrangedIndex)
					newArrangedIndices.append(nextIndex)
				}
				arrangedIndices = newArrangedIndices
			default:
				arrangedIndices.swapAt(0, 1) // This should be a safe change to the indices that doesn't impact the final rendering
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

	mutating func deselectTiles() {
		for index in 0..<game.tiles.count {
			game.tiles[index].isSelected = false
			game.tiles[index].isTracking = false
		}
		arrangedIndices.swapAt(0, 1) // This should be a safe change to the indices that doesn't impact the final rendering
	}
}

public extension Comparable {

	func bounded(by limits: ClosedRange<Self>) -> Self {
		return min(max(self, limits.lowerBound), limits.upperBound)
	}
}

public extension CGVector {

	init(fromDragGesture gesture: DragGesture.Value) {
		self.init(dx: gesture.translation.width, dy: gesture.translation.height)
	}

	var length: CGFloat {
		sqrt(pow(dx, 2) + pow(dy, 2))
	}
}
