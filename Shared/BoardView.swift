//
//  BoardView.swift
//  davestiles
//
//  Created by The App Studio LLC on 7/1/21.
//

import SwiftUI

struct BoardView: View {

	static let standardDuration: Double = 0.1

	let gameFadeDuration = standardDuration
	let popDuration = standardDuration
	let slideDuration = standardDuration
	let surpriseDuration = standardDuration * 2

	@ObservedObject var game: Game
	@Binding var gameState: GameView.GameState
	@State var tracking = false
	let interactive: Bool

	init(game: Game, gameState: Binding<GameView.GameState>, interactive: Bool = true) {
		self.game = game
		self.interactive = interactive
		_gameState = gameState
	}

	func completeMove(rollback: Bool) {
		// TODO: Use await to simply proceed after the time has occurred (so that this is cancellable)
		guard let movementGroup = game.movementGroup else { return }
		// Grab the currently "selected" tiles before leaving (so that we may deselect them)
		let tilesToDeselect = movementGroup.tileIdentifiers
		let duration: Double
		if movementGroup.willMoveNext, !rollback {
			duration = slideDuration * (1 - movementGroup.lastPercentChange)
			game.applyRenderState(.released(percent: movementGroup.lastPercentChange), to: movementGroup.tileIdentifiers)
			if movementGroup.possibleTouch {
				SoundEffects.default.play(.slide)
			}
			game.moves += 1
			// TODO: .drag will need to know the drop destination, so that we can remove and append appropriately
			guard var openTile = game.tiles.firstIndex(where: { $0.id == game.openTileId }) else { return }
			for index in movementGroup.indices(in: game) {
				game.tiles.swapAt(openTile, index)
				openTile = index
			}
		} else { // Undo the current move, which means the percent change also needs to be reversed
			duration = slideDuration * movementGroup.lastPercentChange
			game.applyRenderState(.released(percent: 1 - movementGroup.lastPercentChange), to: movementGroup.tileIdentifiers)
		}
		game.lingeringTileIdentifiers = movementGroup.tileIdentifiers
		game.movementGroup = nil // TODO: Can we keep this until the block below? It will help layout
		DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
			game.applyRenderState(.none(selected: false), to: tilesToDeselect)
			DispatchQueue.main.asyncAfter(deadline: .now() + popDuration) {
				game.lingeringTileIdentifiers.removeAll(where: tilesToDeselect.contains)
			}
			guard game.isFinished else { return }
			finishGame()
		}
	}

	func randomMove() {
		// TODO: Improve this process -- for one, we should not allow gestures to function while this is happening
		let indices = game.movementGroup?.indices(in: game)
		completeMove(rollback: true)
		let movedTile = game.randomMove(except: indices)
		let movedTileId = game.tiles[movedTile.to].id
		game.tiles[movedTile.to].renderState = .thrown(selected: true)
		SoundEffects.default.play(.jump)
		DispatchQueue.main.asyncAfter(deadline: .now() + surpriseDuration) {
			guard let index = game.tiles.firstIndex(where: { $0.id == movedTileId }) else { return }
			game.tiles[index].renderState = .none(selected: false)
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

	func newGame() {
		newGame(firstAppearance: false)
	}

	func newGame(firstAppearance: Bool) {
		// TODO: Use await to chain state changes after a delay
		let startNew = {
			SoundEffects.default.play(.newGame)
			let interval: Double = 1.0 / Double(game.tiles.count)
			for index in 0..<game.tiles.count {
				DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * interval) {
					game.tiles[index].renderState = .thrown(selected: false)
					guard index == game.tiles.count - 1 else { return }
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
						gameState = .playing
						for index in 0..<game.tiles.count {
							game.tiles[index].renderState = .none(selected: false)
						}
					}
				}
			}
		}
		if gameState == .new, firstAppearance {
			game.startNewGame()
			DispatchQueue.main.async {
				startNew()
			}
		} else if !firstAppearance {
			for index in 0..<game.tiles.count {
				game.tiles[index].renderState = .fading
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + gameFadeDuration) {
				gameState = .new
				game.startNewGame()
				DispatchQueue.main.async {
					startNew()
				}
			}
		}
	}

	func tileMovementAnimation(_ tile: Tile) -> Animation? {
		guard interactive else { return nil }
		switch tile.renderState {
		case .none: return .linear(duration: popDuration) // This is for selection
		case .dragged: return nil
		case .fading: return .linear(duration: gameFadeDuration)
		case .lifted: return nil
		case .released(let percent): return .linear(duration: slideDuration * (1.0 - percent))
		case .thrown(let selected): return selected ? .linear(duration: surpriseDuration) : .spring(dampingFraction: 0.75, blendDuration: 1.0)
		case .unset: return nil
		}
	}

	func tileOffset(_ tile: Tile) -> CGSize {
		guard tile.renderState == .dragged else { return .zero }
		guard let movementGroup = game.movementGroup else { return .zero }
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
		guard game.movementGroup == nil || game.movementGroup!.isTracking(tile, in: game) else { return false }
		// TODO: Don't allow gestures for "lingering" tile moves
		return true
	}

	var body: some View {
		GeometryReader { geometry in
			let boardGeometry = BoardGeometry(game: game, geometryProxy: geometry)
			let dragGesture = DragGesture(minimumDistance: 0).onChanged { value in
				switch (game.movementGroup, tracking) {
				case (.none, false):
//					print("updating(new): \(value.translation)")
					guard game.startDrag(value, with: boardGeometry) else { return }
					tracking = true
				case (.some, true):
//					print("updating(tracking): \(value.translation)")
					game.applyRenderState(.dragged, to: game.movementGroup!.tileIdentifiers) // TODO: Find a way to do this only once (or determine it is always necessary)
					if game.movementGroup!.applyDragGestureCrossedMidpoint(value) {
						SoundEffects.default.play(.slide)
					}
				default:
					break
				}
			}
			.onEnded { value in
//				print("onEnded: \(value.translation)")
				tracking = false
				completeMove(rollback: false)
			}
			ZStack {
				let sortedTiles = game.tiles.sorted { leftTile, rightTile in
					// A random throw is _always_ at the end of the sorted list (i.e. on top)
					if case .thrown(let selected) = leftTile.renderState, selected {
						return false
					}
					if case .thrown(let selected) = rightTile.renderState, selected {
						return true
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
							.animation(tile.isFalling ? .easeIn(duration: 1) : nil)
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
		guard ![.drag, .none].contains(movementGroup.direction) else { return true }
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
		BoardView(game:Game(rows: 5, columns: 3), gameState: $gameState)
    }
}
