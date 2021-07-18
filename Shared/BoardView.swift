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
		boardRendering.randomMove()
	}

	func newGame() {
		// TODO: Find a way to chain these state changes to the animation completions
		assert(gameState != .starting)
		let startNew = {
			gameState = .starting
			DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
				self.gameState = .playing
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
		// TODO: We want a more complex animation state (so that pop ups can animate)
		switch gameState {
		case .new: return nil
		case .starting: return .spring(dampingFraction: 0.5, blendDuration: 1.0)
		case .closing: return .linear(duration: 0.1)
		default: return tile.isMoving ? nil : .linear(duration: 0.1)
		}
	}

	func tileOpacity(_ tile: Tile) -> Double {
		switch gameState {
		case .closing: return 0
		default: return tile.isOpen && !boardRendering.game.isFinished ? 0 : 1
		}
	}

	func tilePosition(_ tile: Tile, with position: CGPoint, in geometry: GeometryProxy) -> CGPoint {
		switch gameState {
		case .starting: // TODO: This should be based on throwing each tile sequentially
//			let percent: Double = timeToAnimate - floor(timeToAnimate)
//			print("game starting percent(\(tile.id)): \(percent)")
//			guard Double(tile.id) / Double(boardRendering.game.tiles.count) < percent else { return position }
//			fallthrough
			return position
		case .new: return CGPoint(x: geometry.size.width / 2, y: geometry.size.height * 1.25)
		default: return position
		}
	}

	func useTileGesture(_ tile: Tile) -> Bool {
		guard gameState == .playing, !boardRendering.game.isFinished else { return false }
		return !boardRendering.tracking || tile.isTracking
	}

	var body: some View {
		ZStack {
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
						gameState = .finishing
						SoundEffects.default.play(.gameWin)
					}
				}
				ZStack {
					ForEach(boardRendering.arrangedTiles(with: boardGeometry), id: \.tile.id) { tile, image, position, isMatched in
						TileView(tile: tile, image: image, isMatched: isMatched)
							.opacity(tileOpacity(tile))
							.position(tilePosition(tile, with: position, in: geometry))
							.offset(tile.isMoving ? CGSize(width: boardRendering.positionOffset.dx, height: boardRendering.positionOffset.dy) : .zero)
//							.animation(.linear(duration: 0.2 * (1 - boardRendering.lastPercentChange))) // This causes forever builds
							.animation(tileAnimation(tile))
							.frame(width: boardGeometry.tileSize.width, height: boardGeometry.tileSize.height)
							.gesture(useTileGesture(tile) ? dragGesture : nil)
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

struct BoardView_Previews: PreviewProvider {

    static var previews: some View {
		BoardView(game: Game(rows: 5, columns: 3))
    }
}
