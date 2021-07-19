//
//  BoardView.swift
//  davestiles
//
//  Created by The App Studio LLC on 7/1/21.
//

import SwiftUI

struct BoardView: View {

	@State var boardRendering: BoardRendering
	@State var gameState: GameState = .new

	enum GameState {
		case new		// Tiles are off-screen at the bottom
		case starting	// Tiles flying up from the bottom
		case playing	// Normal game-play state
		case finishing	// TODO: Begin border around the finished picture
		case finished	// TODO: Create state change from finishing->finished
		case closing	// Tiles fading away
	}

	init(game: Game) {
		boardRendering = BoardRendering(game: game)
	}

	func randomMove() {
		// TODO: Improve this process -- for one, we should not allow gestures to function while this is happening
		let movedTile = boardRendering.randomMove()
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
			boardRendering.completeRandomMove(movedTile)
		}
	}

	func finishGame() {
		gameState = .finishing
		SoundEffects.default.play(.gameWin)
		print("Playing \(boardRendering.game.tiles.count) sounds...")
		let totalDuration = Double(boardRendering.game.tiles.count) / 2.0
		for index in 0..<boardRendering.game.tiles.count {
			let delay = Double.random(in: 1.0..<totalDuration)
			DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
				print(" - \(index).click")
				SoundEffects.default.play(.click)
				boardRendering.throwTile(at: index)
				guard index == boardRendering.game.tiles.count - 1 else { return }
			}
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration + 2.0) {
			print("Finished")
			boardRendering.stopThrowingTiles()
			self.gameState = .finished
		}
	}

	func newGame() {
		// TODO: Use await to chain state changes after a delay
		assert(gameState != .starting)
		let startNew = {
			SoundEffects.default.play(.newGame)
			gameState = .starting
			let interval: Double = 1.0 / Double(boardRendering.game.tiles.count)
			for index in 0..<boardRendering.game.tiles.count {
				DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * interval) {
					boardRendering.throwTile(at: index)
					guard index == boardRendering.game.tiles.count - 1 else { return }
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
						boardRendering.stopThrowingTiles()
						self.gameState = .playing
					}
				}
			}
		}
		if gameState == .new {
			startNew()
		} else {
			gameState = .closing
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
				boardRendering.startNewGame()
				self.gameState = .new
				DispatchQueue.main.async {
					startNew()
				}
			}
		}
	}

	func tileAnimation(_ tile: Tile) -> Animation? {
		switch gameState {
		case .new: return nil
		case .starting: return .spring(dampingFraction: 0.75, blendDuration: 1.0)
		case .closing: return .linear(duration: 0.1)
		default: // Here we will create a different duration for random moves
			guard !tile.isMoving else { return nil }
			return .linear(duration: tile.isSelected ? 0.1 : 0.1)
		}
	}

	func tileOffset(_ tile: Tile) -> CGSize {
		guard gameState == .playing else { return .zero }
		return tile.isMoving ? CGSize(width: boardRendering.positionOffset.dx, height: boardRendering.positionOffset.dy) : .zero
	}

	func tileOpacity(_ tile: Tile) -> Double {
		switch gameState {
		case .closing: return 0
		default: return tile.isOpen && !boardRendering.game.isFinished ? 0 : 1
		}
	}

	func tilePosition(_ tile: Tile, with position: CGPoint, in geometry: GeometryProxy) -> CGPoint {
		switch gameState {
		case .starting:
			if tile.isMoving { return position }
			fallthrough
		case .new: return CGPoint(x: geometry.size.width / 2, y: geometry.size.height * 1.25)
		default: return position
		}
	}

	func useTileGesture(_ tile: Tile) -> Bool {
		guard gameState == .playing, !boardRendering.game.isFinished else { return false }
		return !boardRendering.tracking || tile.isTracking
	}

	var body: some View {
		GeometryReader { geometry in
			let boardGeometry = boardRendering.boardGeometry(from: geometry)
			let dragGesture = DragGesture(minimumDistance: 0).onChanged { value in
				if boardRendering.tracking {
					boardRendering.continueTracking(dragGesture: value)
				} else {
					guard let touchedTileIndex = boardRendering.tileIndex(from: value.startLocation, with: boardGeometry) else { return }
					let movementGroup = boardRendering.game.tileMovementGroup(startingWith: touchedTileIndex)
					guard movementGroup.direction != .drag else { return }
					boardRendering.startTracking(movementGroup: movementGroup, from: value, with: boardGeometry)
				}
			}
			.onEnded { value in
				// TODO: Use await to simply proceed after the time has occurred (so that this is cancellable)
				boardRendering.stopTracking()
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.1 * (1 - boardRendering.lastPercentChange)) {
					boardRendering.deselectTiles()
					guard boardRendering.game.isFinished else { return }
					finishGame()
				}
			}
			ZStack {
				ForEach(boardRendering.arrangedTiles(with: boardGeometry), id: \.tile.id) { tile, image, position, isMatched in
					TileView(tile: tile, image: image, isMatched: isMatched, showNumber: gameState.showsLabels)
						.frame(width: boardGeometry.tileSize.width, height: boardGeometry.tileSize.height)
						.position(tilePosition(tile, with: position, in: geometry))
						.offset(tileOffset(tile))
//						.animation(.linear(duration: 0.2 * (1 - boardRendering.lastPercentChange))) // This causes forever builds
						.opacity(tileOpacity(tile))
						.animation(tileAnimation(tile))
						.gesture(useTileGesture(tile) ? dragGesture : nil)
				}
//				.overlay(boardRendering.game.isFinished ? Color.yellow : nil)
				if gameState.liftLabels {
					ForEach(boardRendering.arrangedLabels(with: boardGeometry), id: \.tile.id) { tile, _, position in
						TileView.styledLabel(for: tile)
							.position(position)
							.offset(tile.isMoving ? CGSize(width: 0, height: boardGeometry.boardSize.height * 1.25) : .zero)
							.animation(.easeIn(duration: 1))
					}
				}
			}
		}
		.onAppear {
			DispatchQueue.main.async { newGame() }
		}
		.toolbar {
			ToolbarItemGroup(placement: .navigationBarTrailing) {
				Button(action: randomMove) {
					Label("Random Move", systemImage: "sparkles")
				}
				.disabled([.new, .starting, .finished, .finishing, .closing].contains(gameState))
				Button(action: newGame) {
					Label("New Game", systemImage: "restart.circle")
				}
				.disabled([.new, .starting, .closing].contains(gameState))
			}
		}
    }
}

extension BoardView.GameState {

	var showsLabels: Bool {
		![.finished, .finishing].contains(self)
	}

	var liftLabels: Bool {
		[.finishing].contains(self)
	}
}

struct BoardView_Previews: PreviewProvider {

    static var previews: some View {
		BoardView(game: Game(rows: 5, columns: 3))
    }
}
