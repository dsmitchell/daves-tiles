//
//  GameView.swift
//  davestiles
//
//  Created by The App Studio LLC on 7/7/21.
//

import SwiftUI

struct GameView: View {

	static let gameFadeDuration = BoardView.standardDuration

	@ObservedObject var game: Game
	@Binding var gameState: GameState
	@Binding var presenterVisible: Bool

	enum GameState {
		case new		// Tiles are off-screen at the bottom
		case playing	// Normal game-play state
	}

    var body: some View {
		let boardView = BoardView(game: game, gameState: $gameState)
		ZStack {
//			Color.gray
//				.edgesIgnoringSafeArea([.bottom, .leading, .trailing])
			boardView
				.edgesIgnoringSafeArea(.bottom)
				.padding(4)
				.scaleEffect(0.99999) // This allows for great rotation behavior (and smoother animation??)
//				.drawingGroup() // Must be after padding to avoid clipping // This is known to cause animation issues
		}
		.onChange(of: presenterVisible) { newValue in
			// This is the equivalent of viewDidAppear (because the presenter is now onDisappear)
			print("Presenter visible: \(newValue)")
			guard !presenterVisible else { return }
			newGame(firstAppearance: true)
		}
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItemGroup(placement: .principal) {
				Text("Moves: \(game.moves)")
			}
			ToolbarItemGroup(placement: .navigationBarTrailing) {
				Button(action: boardView.randomMove) {
					Label("Random Move", systemImage: "sparkles")
				}
				.disabled([.new].contains(gameState))
				Button(action: newGame) { // TODO: Decide whether we need a new `Game` instance
					Label("New Game", systemImage: "restart.circle")
				}
				.disabled([.new].contains(gameState))
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
			DispatchQueue.main.asyncAfter(deadline: .now() + GameView.gameFadeDuration) {
				gameState = .new
				game.startNewGame()
				DispatchQueue.main.async {
					startNew()
				}
			}
		}
	}
}

struct GameView_Previews: PreviewProvider {

	static let game = Game(rows: 6, columns: 4)
	@State static var gameState: GameView.GameState = .new
	@State static var presenterVisible = false
	
    static var previews: some View {
		GameView(game: game, gameState: $gameState, presenterVisible: $presenterVisible)
    }
}
