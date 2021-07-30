//
//  GameView.swift
//  davestiles
//
//  Created by The App Studio LLC on 7/7/21.
//

import SwiftUI

struct GameView: View {

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
			boardView.newGame(firstAppearance: true)
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
				Button(action: boardView.newGame) { // TODO: Decide whether we need a new `Game` instance
					Label("New Game", systemImage: "restart.circle")
				}
				.disabled([.new].contains(gameState))
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
