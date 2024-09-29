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
	
	enum CompleteMoveBehavior {
		case rollback
		case proceed(swappingIdentifier: Int)
	}

	@State var game: Game
	@State var movementGroup: TileMovementGroup?
	@State var lingeringTileIdentifiers = [Int]()

	struct SwapInfo: Equatable {
		let indices: [Int]
		let enabled: Bool
	}
	let swaps: SwapInfo?

	func completeMove(behavior: CompleteMoveBehavior) {
		guard let movementGroup = movementGroup else { return }

		let duration: Double
		switch behavior {
		case .proceed(let swappingIdentifier):
			if movementGroup.numberOfMidpointCrossings % 2 == 0 {
				SoundEffects.default.play(.slide)
			}
			duration = movementGroup.direction == .drag ? surpriseDuration : slideDuration * (1 - movementGroup.lastPercentChange)
			lingeringTileIdentifiers = [swappingIdentifier] + movementGroup.tileIdentifiers
			game.moves += 1
			if duration > 0 {
				if movementGroup.direction == .drag {
					game.applyRenderState(.thrown, to: [swappingIdentifier] + movementGroup.tileIdentifiers)
				} else {
					game.applyRenderState(.released(percent: movementGroup.lastPercentChange), to: movementGroup.tileIdentifiers)
				}
			}
			guard var swapIndex = game.tiles.firstIndex(where: { $0.id == swappingIdentifier }) else { return }
			for index in movementGroup.indices(in: game) {
				game.tiles.swapAt(swapIndex, index)
				swapIndex = index
			}
		case .rollback: // Undo the current move, which means the percent change also needs to be reversed
			duration = slideDuration * movementGroup.lastPercentChange
			lingeringTileIdentifiers = movementGroup.tileIdentifiers
			if duration > 0 {
				game.applyRenderState(.released(percent: 1 - movementGroup.lastPercentChange), to: movementGroup.tileIdentifiers)
			}
		}
		self.movementGroup = nil
		Task { await deselectLingeringTiles(after: duration) }
	}

	func deselectLingeringTiles(after duration: Double) async {
		// TODO: explore if/where to support Task cancellation
		let tilesToDeselect = lingeringTileIdentifiers
		let deselectionCount = tilesToDeselect.filter { identifier in
			game.tiles.first(where: { $0.id == identifier })!.isSelected
		}.count
		if duration > 0 {
			try? await Task.sleep(nanoseconds: UInt64(Double(GameView.oneSecond) * duration))
		}
		game.applyRenderState(.transitioning(toSelected: false), to: tilesToDeselect)
		if deselectionCount > 0 {
			try? await Task.sleep(nanoseconds: UInt64(Double(GameView.oneSecond) * popDuration))
		}
		game.applyRenderState(.none, to: tilesToDeselect)
		lingeringTileIdentifiers.removeAll(where: tilesToDeselect.contains)
		guard game.isFinished else { return }
		game.state = .finished
	}

	func randomMove() async {
		// TODO: Improve this process -- for one, we should not allow gestures to function while this is happening
		let indices = movementGroup?.indices(in: game)
		completeMove(behavior: .rollback)
		let movedTileIndices = game.randomMove(except: indices)
		let movedTileIds = movedTileIndices.map { index in
			game.tiles[index].id
		}
		for index in movedTileIndices {
			game.tiles[index].renderState = .thrown
		}
		SoundEffects.default.play(.jump)
		let interval = Double(GameView.oneSecond) * surpriseDuration
		try? await Task.sleep(nanoseconds: UInt64(interval))
		movedTileIds.compactMap({ id in game.tiles.firstIndex(where: { $0.id == id }) }).forEach { index in
			game.tiles[index].renderState = .none
		}
		guard game.isFinished else { return }
		game.state = .finished
	}
	
	func swapAnimation(_ tile: Tile) -> Animation? {
		guard let swaps = swaps else { return nil }
		guard let index = game.tiles.firstIndex(where: { $0.id == tile.id }), swaps.indices.contains(index) else { return nil }
		return .linear(duration: surpriseDuration * 2)
	}

	func tileMovementAnimation(_ tile: Tile) -> Animation? {
		guard swaps == nil else { return nil }
		switch tile.renderState {
		case .none: return game.state == .new ? .spring(dampingFraction: 0.75, blendDuration: 1.0) : nil
		case .released(let percent) where percent < 1.0: return .linear(duration: slideDuration * (1.0 - percent))
		case .thrown: return .linear(duration: surpriseDuration)
		case .transitioning: return .linear(duration: popDuration)
		default: return nil
		}
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
		guard swaps == nil, tile.renderState == .dragged, let movementGroup = movementGroup else { return .zero }
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
#if os(visionOS)
		if case .unset = tile.renderState, game.state == .new {
			return 0
		}
#endif
		guard isOpen && game.state != .finished else { return 1 }
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

	func trackingPosition(for tile: Tile) -> Int? {
		return lingeringTileIdentifiers.firstIndex(of: tile.id) ?? movementGroup?.tileIdentifiers.firstIndex(of: tile.id)
	}

	func useTileGesture(_ tile: Tile) -> Bool {
		guard swaps == nil, game.state == .playing else { return false }
#if os(visionOS) // Temporary workaround for gestures continuing on visionOS
		guard lingeringTileIdentifiers.isEmpty else { return false }
#endif
		guard movementGroup == nil || movementGroup!.isTracking(tile, in: game) || movementGroup!.direction == .drag else { return false }
		return true
	}

	var body: some View {
		GeometryReader { geometry in
			let boardGeometry = BoardGeometry(game: game, geometryProxy: geometry)
			let dragGesture = DragGesture(minimumDistance: 0).onChanged { value in
				switch movementGroup {
				case .none where value.velocity == .zero:
					guard let movementGroup = game.startDrag(value, with: boardGeometry) else { return }
					self.movementGroup = movementGroup
					if movementGroup.direction == .drag {
						SoundEffects.default.play(.popUp)
					}
				case .some(let movementGroup) where movementGroup.direction != .none && movementGroup.trackingState != nil:
					game.applyRenderState(.dragged, to: movementGroup.tileIdentifiers)
					if self.movementGroup!.applyDragGestureCrossedMidpoint(value) {
						SoundEffects.default.play(.slide)
					}
				case .some(let movementGroup) where movementGroup.trackingState == nil:
					guard let tappedTileIndex = boardGeometry.tileIndex(from: value.location) else { return }
					if movementGroup.indices(in: game).contains(tappedTileIndex) {
						self.movementGroup?.trackingState = .restarted
					} else {
						completeMove(behavior: .proceed(swappingIdentifier: game.tiles[tappedTileIndex].id))
					}
				default:
					break
				}
			}
			.onEnded { value in
				// Check whether we need to handle Swap mode before completing the touch
				if let movementGroup = movementGroup, movementGroup.direction == .drag, let droppedTileIndex = boardGeometry.tileIndex(from: value.location) {
					if movementGroup.indices(in: game).contains(droppedTileIndex) {
						switch (movementGroup.trackingState, movementGroup.possibleTap) {
						case (.restarted, true):
							SoundEffects.default.play(.popDown)
							fallthrough
						case (.restarted, false):
							lingeringTileIdentifiers = movementGroup.tileIdentifiers
							self.movementGroup = nil
							Task { await deselectLingeringTiles(after: 0) }
						case (_, false):
							completeMove(behavior: .rollback)
						default:
							self.movementGroup?.trackingState = nil
						}
					} else { // We're dropping onto another tile
						completeMove(behavior: .proceed(swappingIdentifier: game.tiles[droppedTileIndex].id))
					}
				} else if let movementGroup = movementGroup, movementGroup.willMoveNext, let openTileId = game.openTileId {
					completeMove(behavior: .proceed(swappingIdentifier: openTileId))
				} else {
					completeMove(behavior: .rollback)
				}
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
					switch (trackingPosition(for: leftTile), trackingPosition(for: rightTile)) {
					case (.none, .some): return true
					case (.some(let leftPosition), .some(let rightPosition)): return leftPosition < rightPosition
					default: return false
					}
				}
				ForEach(sortedTiles) { tile in
					let index = index(for: tile)
					let isMatched = game.isMatched(tile: tile, index: index)
					let isOpen = tile.id == game.openTileId
					let showNumber = ![.finished, .fading].contains(game.state)
					let image = boardGeometry.image(for: tile.id)
					TileView(id: tile.id, image: image, isSelected: tile.isSelected, isMatched: isMatched, showNumber: showNumber, text: boardGeometry.text(for: tile.id))
						.id("tile.\(tile.id)")
						.frame(width: boardGeometry.tileSize.width, height: boardGeometry.tileSize.height)
						.position(tilePosition(tile, with: boardGeometry.positions[index], in: geometry))
						.offset(tileOffset(tile))
#if os(visionOS)
						.offset(z: tileOffsetZ(tile))
						.hoverEffect(isEnabled: useTileGesture(tile))
#endif
						.opacity(tileOpacity(tile, isOpen: isOpen))
						.animation(swapAnimation(tile), value: swaps)
						.animation(tileMovementAnimation(tile), value: tile.renderState)
						.gesture(!isOpen && useTileGesture(tile) ? dragGesture : nil)
				}
				if swaps == nil, game.state == .finished {
					ForEach(game.tiles) { tile in
						TileView.styledLabel(with: boardGeometry.text(for: tile.id), for: tile.id)
							.position(boardGeometry.positions[tile.id-1])
#if os(visionOS)
							.offset(z: tile.isFalling ? 384 : 0)
#else
							.offset(x: 0, y: tile.isFalling ? boardGeometry.boardSize.height * 3 : 0)
#endif
							.opacity(tile.isFalling ? 0 : 1) // Fade out while falling
							.animation(tileFallingAnimation(tile), value: tile.renderState)
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

	func startDrag(_ dragGesture: DragGesture.Value, with boardGeometry: BoardGeometry) -> TileMovementGroup? {
		guard let touchedTileIndex = boardGeometry.tileIndex(from: dragGesture.startLocation) else { return nil }
		guard tiles[touchedTileIndex].id != openTileId else { return nil } // Sometimes the boardGeometry returns the Open Tile
		var movementGroup = TileMovementGroup(startingWith: touchedTileIndex, in: self)
		guard ![.none].contains(movementGroup.direction) else { return movementGroup }
		movementGroup.applyMovementFunction(for: dragGesture, with: boardGeometry)
		applyRenderState(.transitioning(toSelected: true), to: movementGroup.tileIdentifiers)
		return movementGroup
	}
}

fileprivate extension Tile {

	var isFalling: Bool {
		switch renderState {
		case .unset, .falling: return true // Unset ensures detatched numbers are not prematurely drawn on the playing field
		default: return false
		}
	}
}

#Preview {
	return BoardView(game:Game(rows: 5, columns: 3, mode: .swap), swaps: nil)
}
