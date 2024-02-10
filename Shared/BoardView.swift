//
//  BoardView.swift
//  daves-tiles
//
//  Created by The App Studio LLC on 7/1/21.
//  Copyright © 2021 The App Studio LLC.
//

import SwiftUI

struct BoardView: View {

	static let standardDuration: Double = 0.1

	let popDuration = standardDuration
	let slideDuration = standardDuration
	let surpriseDuration = standardDuration * 2

	enum TrackingState {
		case initial
		case restarted
		case ignored
	}

	@ObservedObject var game: Game
	@Binding var gameState: GameView.GameState
	@State var trackingState: TrackingState?

	struct SwapInfo: Equatable {
		let indices: [Int]
		let enabled: Bool
	}
	let swaps: SwapInfo?

	init(game: Game, gameState: Binding<GameView.GameState>, swaps: SwapInfo? = nil) {
		self.game = game
		self.swaps = swaps
		_gameState = gameState
	}

	func completeMove(rollback: Bool) {
		guard let movementGroup = game.movementGroup else { return }

		let duration: Double
		if movementGroup.direction == .drag, movementGroup.willMoveNext, !rollback {
			guard let swappingIdentifier = movementGroup.swappingIdentifier else { fatalError("No swapping tile index") }
			if movementGroup.numberOfMidpointCrossings % 2 == 0 {
				SoundEffects.default.play(.slide)
			}
			duration = surpriseDuration
			game.moves += 1
			game.applyRenderState(.thrown, to: [swappingIdentifier] + movementGroup.tileIdentifiers)
			guard var swapIndex = game.tiles.firstIndex(where: { $0.id == swappingIdentifier }) else { return }
			for index in movementGroup.indices(in: game) {
				game.tiles.swapAt(swapIndex, index)
				swapIndex = index
			}
		} else if movementGroup.willMoveNext, !rollback {
			guard let swappingIdentifier = movementGroup.swappingIdentifier else { fatalError("No open tile index") }
			if movementGroup.numberOfMidpointCrossings % 2 == 0 {
				SoundEffects.default.play(.slide)
			}
			duration = slideDuration * (1 - movementGroup.lastPercentChange)
			game.moves += 1
			game.applyRenderState(.released(percent: movementGroup.lastPercentChange), to: movementGroup.tileIdentifiers)
			guard var swapIndex = game.tiles.firstIndex(where: { $0.id == swappingIdentifier }) else { return }
			for index in movementGroup.indices(in: game) {
				game.tiles.swapAt(swapIndex, index)
				swapIndex = index
			}
		} else { // Undo the current move, which means the percent change also needs to be reversed
			duration = slideDuration * movementGroup.lastPercentChange
			game.applyRenderState(.released(percent: 1 - movementGroup.lastPercentChange), to: movementGroup.tileIdentifiers)
		}
		deselectTiles(in: movementGroup, after: duration)
	}

	func deselectTiles(in movementGroup: TileMovementGroup, after duration: Double) {
		// TODO: Use await to simply proceed after the time has occurred (so that this is cancellable)
		let tilesToDeselect = movementGroup.swappingIdentifier == nil ? movementGroup.tileIdentifiers : [movementGroup.swappingIdentifier!] + movementGroup.tileIdentifiers
		game.lingeringTileIdentifiers = tilesToDeselect
		game.movementGroup = nil
		let deselect = {
			game.applyRenderState(.none(selected: false), to: tilesToDeselect)
			DispatchQueue.main.asyncAfter(deadline: .now() + popDuration) {
				game.lingeringTileIdentifiers.removeAll(where: tilesToDeselect.contains)
				guard game.isFinished else { return }
				gameState = .finished
			}
		}
		if duration == 0 {
			deselect()
		} else {
			DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: deselect)
		}
	}

	func randomMove() {
		// TODO: Improve this process -- for one, we should not allow gestures to function while this is happening
		// TODO: Improve the randomMove() in SwapMode (I think this is done already)
		let indices = game.movementGroup?.indices(in: game)
		completeMove(rollback: true)
		let movedTileIndices = game.randomMove(except: indices)
		let movedTileIds = movedTileIndices.map { index in
			game.tiles[index].id
		}
		for index in movedTileIndices {
			game.tiles[index].renderState = .thrown
		}
		SoundEffects.default.play(.jump)
		DispatchQueue.main.asyncAfter(deadline: .now() + surpriseDuration) {
			movedTileIds.compactMap({ id in game.tiles.firstIndex(where: { $0.id == id }) }).forEach { index in
				game.tiles[index].renderState = .none(selected: false)
			}
			guard game.isFinished else { return }
			gameState = .finished
		}
	}

	func tileMovementAnimation(_ tile: Tile) -> Animation? {
		guard let swaps = swaps else {
			switch tile.renderState {
			case .none: return gameState == .new ? .spring(dampingFraction: 0.75, blendDuration: 1.0) : .linear(duration: popDuration)
			case .fading: return .linear(duration: GameView.gameFadeDuration)
			case .released(let percent): return .linear(duration: slideDuration * (1.0 - percent))
			case .thrown: return .linear(duration: surpriseDuration)
			default: return nil
			}
		}
		guard let index = game.tiles.firstIndex(where: { $0.id == tile.id }), swaps.indices.contains(index) else { return nil }
		return .linear(duration: surpriseDuration * 2)
	}
	
	func tileFallingAnimation(_ tile: Tile) -> Animation? {
		guard tile.isFalling else { return nil }
		#if os(visionOS)
		return .easeOut(duration: 0.5)
		#else
		return .easeIn(duration: 1)
		#endif
	}

	func tileOffset(_ tile: Tile) -> CGSize {
		guard swaps == nil, tile.renderState == .dragged, let movementGroup = game.movementGroup else { return .zero }
		return CGSize(width: movementGroup.positionOffset.dx, height: movementGroup.positionOffset.dy)
	}
	
	func tileOffsetZ(_ tile: Tile) -> Double {
		guard let swaps = swaps else {
			guard tile.renderState == .unset else {
				return tile.isSelected ? 8 : 0
			}
			return 640
		}
		if swaps.enabled, let index = game.tiles.firstIndex(where: { $0.id == tile.id }), swaps.indices.contains(index) {
			return 8
		}
		return tile.isSelected ? 8 : 0
	}

	func tileOpacity(_ tile: Tile, isOpen: Bool) -> Double {
		guard swaps == nil else { return isOpen ? 0 : 1 }
		guard tile.isFading || isOpen && gameState != .finished else { return 1 }
		return 0
	}

	func tilePosition(_ tile: Tile, with position: CGPoint, in geometry: GeometryProxy) -> CGPoint {
		guard swaps == nil, tile.renderState == .unset else { return position }
#if os(visionOS)
		return CGPoint(x: tile.id % 2 == 0 ? 0 : geometry.size.width, y: geometry.size.height / 2)
#else
		return CGPoint(x: geometry.size.width / 2, y: geometry.size.height * 1.25)
#endif
	}

	func useTileGesture(_ tile: Tile) -> Bool {
		guard swaps == nil, gameState == .playing else { return false }
		guard game.movementGroup == nil || game.movementGroup!.isTracking(tile, in: game) || game.movementGroup!.direction == .drag else { return false }
		return true
	}

	var body: some View {
		GeometryReader { geometry in
			let boardGeometry = BoardGeometry(game: game, geometryProxy: geometry)
			let dragGesture = DragGesture(minimumDistance: 0).onChanged { value in
				switch (game.movementGroup, trackingState) {
				case (.none, .none):
					guard game.startDrag(value, with: boardGeometry) else { return }
					if game.movementGroup?.direction == .drag {
						SoundEffects.default.play(.popUp)
					}
					trackingState = .initial
				case (.some, .some(let state)) where state != .ignored:
					game.applyRenderState(.dragged, to: game.movementGroup!.tileIdentifiers) // TODO: Find a way to do this only once (or determine it is always necessary)
					if game.movementGroup!.applyDragGestureCrossedMidpoint(value) {
						SoundEffects.default.play(.slide)
					}
				case (.some(let movementGroup), .none):
					assert(movementGroup.direction == .drag)
					guard let tappedTileIndex = boardGeometry.tileIndex(from: value.location) else { return }
					if movementGroup.indices(in: game).contains(tappedTileIndex) {
//						print("restarting tracking of \(tappedTileIndex): \(value.translation)")
						trackingState = .restarted
					} else {
//						print("new tile selected: \(tappedTileIndex)")
						game.movementGroup?.swappingIdentifier = game.tiles[tappedTileIndex].id
						game.movementGroup?.willMoveNext = true
						completeMove(rollback: false)
						trackingState = .ignored
					}
				default:
					print("Doing nothing! \(String(describing: trackingState))")
					break
				}
			}
			.onEnded { value in
//				print("onEnded: \(value.translation)")
				// Check whether we need to handle Swap mode before completing the touch
				defer {
					trackingState = nil
				}
				if let movementGroup = game.movementGroup, movementGroup.direction == .drag, let droppedTileIndex = boardGeometry.tileIndex(from: value.location) {
					if movementGroup.indices(in: game).contains(droppedTileIndex) {
						switch (trackingState, movementGroup.possibleTap) {
						case (.restarted, true):
							SoundEffects.default.play(.popDown)
							fallthrough
						case (.restarted, false):
							deselectTiles(in: movementGroup, after: 0)
							return
						case (_, false):
							game.movementGroup?.willMoveNext = false
						default:
							return
						}
					} else { // We're dropping onto another tile
						game.movementGroup?.swappingIdentifier = game.tiles[droppedTileIndex].id
						game.movementGroup?.willMoveNext = true
					}
				}
				completeMove(rollback: false)
			}
			ZStack {
				let sortedTiles = game.tiles.sorted { leftTile, rightTile in
					// First check if this is a SwapInfo tile
					if let swaps = swaps, let leftIndex = game.tiles.firstIndex(where: { $0.id == leftTile.id }), let rightIndex = game.tiles.firstIndex(where: { $0.id == rightTile.id }) {
						switch (swaps.indices.firstIndex(of: leftIndex), swaps.indices.firstIndex(of: rightIndex)) {
						case (.none, .some): return true
						case (.some(let leftPosition), .some(let rightPosition)): return leftPosition < rightPosition
						case (.some, _): return false
						default: return leftIndex < rightIndex
						}
					}
					// A random throw is _always_ at the end of the sorted list (i.e. on top)
					switch (leftTile.renderState, rightTile.renderState) {
					case (.thrown, .thrown): break // let trackingPosition decide
					case (.thrown, _): return false
					case (_, .thrown): return true
					default: break // let trackingPosition decide
					}
					// Otherwise any tile with a tracking position is sorted towards the end
					switch (game.trackingPosition(for: leftTile), game.trackingPosition(for: rightTile)) {
					case (.none, .some): return true
					case (.some(let leftPosition), .some(let rightPosition)): return leftPosition < rightPosition
					default: return false
					}
				}
				ForEach(sortedTiles) { tile in
					let index = index(for: tile)
					let isMatched = game.isMatched(tile: tile, index: index)
					let isOpen = tile.id == game.openTileId
					TileView(tile: tile, image: boardGeometry.image(for: tile), isMatched: isMatched, isOpen: isOpen, showNumber: gameState != .finished, text: boardGeometry.text(for: tile))
#if os(visionOS)
						.hoverEffect(isEnabled: useTileGesture(tile))
#endif
						.id("tile.\(tile.id)")
						.frame(width: boardGeometry.tileSize.width, height: boardGeometry.tileSize.height)
						.position(tilePosition(tile, with: boardGeometry.positions[index], in: geometry))
						.offset(tileOffset(tile))
#if os(visionOS)
						.offset(z: tileOffsetZ(tile))
#endif
						.opacity(tileOpacity(tile, isOpen: isOpen))
						.animation(tileMovementAnimation(tile), value: swaps)
						.animation(tileMovementAnimation(tile), value: tile.renderState)
						.gesture(!isOpen && useTileGesture(tile) ? dragGesture : nil)
				}
				if swaps == nil, gameState == .finished {
					ForEach(game.tiles) { tile in
						TileView.styledLabel(for: tile, with: boardGeometry.text(for: tile))
							.position(boardGeometry.positions[tile.id-1])
#if os(visionOS)
							.offset(z: tile.isFalling ? 384 : 0)
#else
							.offset(tile.isFalling ? CGSize(width: 0, height: boardGeometry.boardSize.height * 3) : .zero)
#endif
							.opacity(tile.isFalling ? 0 : 1) // Fade out while falling
							.animation(tileFallingAnimation(tile), value: tile.isFalling)
					}
				}
			}
		}
    }

	func index(for tile: Tile) -> Int {
		guard let index = game.tiles.firstIndex(of: tile) else { fatalError("Tile with no index: \(tile.id)") }
		guard let swaps = swaps, swaps.enabled, let position = swaps.indices.firstIndex(of: index) else { return index }
		return swaps.indices[(position + 1) % swaps.indices.count]
 	}
}

fileprivate extension Game {

	func startDrag(_ dragGesture: DragGesture.Value, with boardGeometry: BoardGeometry) -> Bool {
		guard let touchedTileIndex = boardGeometry.tileIndex(from: dragGesture.startLocation) else { return false }
		var movementGroup = TileMovementGroup(startingWith: touchedTileIndex, in: self)
		guard ![.none].contains(movementGroup.direction) else { return true }
		movementGroup.applyMovementFunction(for: dragGesture, with: boardGeometry)
		self.movementGroup = movementGroup
		applyRenderState(.none(selected: true), to: movementGroup.tileIdentifiers)
		return true
	}
}

fileprivate extension Tile {

	var isFalling: Bool {
		switch renderState {
		case .unset, .falling: return true // Unset ensures detatched numbers are not prematurely drawn on the playing field
		case .fading(let wasFalling): return wasFalling
		default: return false
		}
	}

	var isFading: Bool {
		guard case .fading = renderState else { return false }
		return true
	}
}

struct BoardView_Previews: PreviewProvider {

	@State static var gameState: GameView.GameState = .playing

    static var previews: some View {
		BoardView(game:Game(rows: 5, columns: 3, mode: .swap), gameState: $gameState)
    }
}
