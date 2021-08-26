//
//  BoardView.swift
//  davestiles
//
//  Created by The App Studio LLC on 7/1/21.
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
	let interactive: Bool

	init(game: Game, gameState: Binding<GameView.GameState>, interactive: Bool = true) {
		self.game = game
		self.interactive = interactive
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
			game.applyRenderState(.thrown(selected: true), to: [swappingIdentifier] + movementGroup.tileIdentifiers)
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
				finishGame()
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
		// TODO: Improve the randomMove() in SwapMode
		let indices = game.movementGroup?.indices(in: game)
		completeMove(rollback: true)
		let movedTileIndices = game.randomMove(except: indices)
		let movedTileIds = movedTileIndices.map { index in
			game.tiles[index].id
		}
		for index in movedTileIndices {
			game.tiles[index].renderState = .thrown(selected: true)
		}
		SoundEffects.default.play(.jump)
		DispatchQueue.main.asyncAfter(deadline: .now() + surpriseDuration) {
			movedTileIds.compactMap({ id in game.tiles.firstIndex(where: { $0.id == id }) }).forEach { index in
				game.tiles[index].renderState = .none(selected: false)
			}
			guard game.isFinished else { return }
			finishGame()
		}
	}

	func finishGame() {
		SoundEffects.default.play(.gameWin)
		let totalDuration = Double(game.tiles.count) / 2.0
		for index in 0..<game.tiles.count {
			let delay = Double.random(in: 1.0..<totalDuration)
			game.tiles[index].renderState = .lifted(falling: false)
			DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
				SoundEffects.default.play(.click)
				game.tiles[index].renderState = .lifted(falling: true)
				guard index == game.tiles.count - 1 else { return }
			}
		}
	}

	func tileMovementAnimation(_ tile: Tile) -> Animation? {
		guard interactive else { return nil }
		switch tile.renderState {
		case .none: return .linear(duration: popDuration)
		case .fading: return .linear(duration: GameView.gameFadeDuration)
		case .released(let percent): return .linear(duration: slideDuration * (1.0 - percent))
		case .thrown(let selected): return selected ? .linear(duration: surpriseDuration) : .spring(dampingFraction: 0.75, blendDuration: 1.0)
		default: return nil
		}
	}

	func tileOffset(_ tile: Tile) -> CGSize {
		guard interactive, tile.renderState == .dragged, let movementGroup = game.movementGroup else { return .zero }
		return CGSize(width: movementGroup.positionOffset.dx, height: movementGroup.positionOffset.dy)
	}

	func tileOpacity(_ tile: Tile, isOpen: Bool) -> Double {
		guard interactive else { return isOpen && !tile.isLifted ? 0 : 1 }
		guard tile.renderState == .fading || isOpen && !game.isFinished else { return 1 }
		return 0
	}

	func tilePosition(_ tile: Tile, with position: CGPoint, in geometry: GeometryProxy) -> CGPoint {
		guard interactive, tile.renderState == .unset else { return position }
		return CGPoint(x: geometry.size.width / 2, y: geometry.size.height * 1.25)
	}

	func useTileGesture(_ tile: Tile) -> Bool {
		guard interactive, gameState == .playing, !game.isFinished else { return false }
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
					// A random throw is _always_ at the end of the sorted list (i.e. on top)
					switch (leftTile.renderState, rightTile.renderState) {
					case (.thrown(true), .thrown(true)): break // let trackingPosition decide
					case (.thrown(true), _): return false
					case (_, .thrown(true)): return true
					default: break // let trackingPosition decide
					}
					// Otherwise any tile with a tracking position is sorted towards the end
					switch (game.trackingPosition(for: leftTile), game.trackingPosition(for: rightTile)) {
					case (.none, .some):
						return true
					case (.some(let leftPosition), .some(let rightPosition)):
						return leftPosition < rightPosition
					default:
						return false
					}
				}
				ForEach(sortedTiles) { tile in
					let index = game.tiles.firstIndex(of: tile)!
					let isMatched = game.isMatched(tile: tile, index: index)
					let isOpen = tile.id == game.openTileId
					TileView(tile: tile, image: boardGeometry.image(for: tile), isMatched: isMatched, isOpen: isOpen, showNumber: !tile.isLifted, text: boardGeometry.text(for: tile))
						.id("tile.\(tile.id)")
						.frame(width: boardGeometry.tileSize.width, height: boardGeometry.tileSize.height)
						.position(tilePosition(tile, with: boardGeometry.positions[index], in: geometry))
						.offset(tileOffset(tile))
						.opacity(tileOpacity(tile, isOpen: isOpen))
						.animation(tileMovementAnimation(tile), value: tile.renderState)
						.gesture(!isOpen && useTileGesture(tile) ? dragGesture : nil)
				}
				if interactive {
					ForEach(game.tiles) { tile in
						let index = game.tiles.firstIndex(of: tile)!
						TileView.styledLabel(for: tile, with: boardGeometry.text(for: tile))
							.position(boardGeometry.positions[index])
							.offset(tile.isFalling ? CGSize(width: 0, height: boardGeometry.boardSize.height * 3) : .zero)
							.animation(tile.isFalling ? .easeIn(duration: 1) : nil, value: tile.isFalling)
							.opacity(tile.isLifted ? 1 : 0)
					}
				}
			}
		}
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
		guard case .lifted(let falling) = renderState, falling else { return false }
		return true
	}

	var isLifted: Bool {
		guard case .lifted = renderState else { return false }
		return true
	}
}

struct BoardView_Previews: PreviewProvider {

	@State static var gameState: GameView.GameState = .playing

    static var previews: some View {
		BoardView(game:Game(rows: 5, columns: 3, mode: .swap), gameState: $gameState)
    }
}
