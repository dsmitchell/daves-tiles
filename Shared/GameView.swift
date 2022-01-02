//
//  GameView.swift
//  daves-tiles
//
//  Created by The App Studio LLC on 7/7/21.
//  Copyright © 2021 The App Studio LLC.
//

import SwiftUI

struct GameView: View {

	static let gameFadeDuration = BoardView.standardDuration
	static let oneSecond = UInt64(960_000_000)

	@ObservedObject var game: Game
	@Binding var gameState: GameState
	@Binding var presenterVisible: Bool
	@State private var initialDate: Date?
	@State private var finishGameTask: Task<Void,Never>?
	@State private var showingWinGameDialog = false
	let randomJumps: Bool

	enum GameState {
		case new		// Tiles are off-screen at the bottom
		case playing	// Normal game-play state
		case finished	// Game is finished
	}

    var body: some View {
		boardView(gameState: $gameState).onChange(of: presenterVisible) { newValue in
			// This is the equivalent of viewDidAppear (because the presenter is now onDisappear)
			print("Presenter visible: \(newValue)")
			guard !presenterVisible else {
				if gameState == .playing, let initialDate = initialDate {
					game.accumulatedTime += Date().timeIntervalSinceReferenceDate - initialDate.timeIntervalSinceReferenceDate
				}
				initialDate = nil
				finishGameTask?.cancel()
				finishGameTask = nil
				return
			}
			newGame(firstAppearance: true)
		}
		.onChange(of: gameState) { newValue in
			switch newValue {
			case .new where finishGameTask != nil:
				finishGameTask!.cancel()
				finishGameTask = nil
			case .finished where initialDate != nil:
				let now = Date()
				game.accumulatedTime += now.timeIntervalSinceReferenceDate - initialDate!.timeIntervalSinceReferenceDate
				initialDate = nil
				finishGameTask = Task(operation: finishGame)
			default: break
			}
		}
		.alert("Congratulations! You won with a time of \(displayTime) in \(game.moves) moves", isPresented: $showingWinGameDialog) {
			Button("Play again", action: newGame)
			Button("Cancel", role: .cancel) { }
		}
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItemGroup(placement: .principal) {
				HStack {
					Text("Moves: \(game.moves)")
					Text("Time: \(displayTime)       ") // Extra spaces works around a bug
				}
			}
			ToolbarItemGroup(placement: .navigationBarTrailing) {
				Button(action: newGame) { // TODO: Decide whether we need a new `Game` instance
					Label("New Game", systemImage: "arrow.clockwise.circle")
				}
				.disabled([.new].contains(gameState))
			}
		}
    }

	@ViewBuilder
	func boardView(gameState: Binding<GameState>) -> some View {
		let board = BoardView(game: game, gameState: gameState)
		let wrappedBoard = board
			.edgesIgnoringSafeArea(.bottom)
			.padding(4)
//			.scaleEffect(0.99999) // This allows for great rotation behavior (and smoother animation??)
//			.drawingGroup() // Must be after padding to avoid clipping // This is known to cause animation issues
		if let initialDate = initialDate, gameState.wrappedValue == .playing {
			TimelineView(.periodic(from: initialDate, by: 1.0)) { context in
				wrappedBoard
			}
			.task {
				guard randomJumps else { return }
				defer {
					print("Exiting random jump timer")
				}

				let delayInSeconds = Double(game.openTileId == nil ? game.tiles.count - min(game.columns, game.rows) : game.tiles.count * 2)
				// The initial delay needs to take into account the current time
				let currentGameTime = game.accumulatedTime + Date().timeIntervalSinceReferenceDate - initialDate.timeIntervalSinceReferenceDate
				let initialDelay = delayInSeconds - currentGameTime.truncatingRemainder(dividingBy: delayInSeconds)
				print("Starting random jump timer after \(initialDelay)s...")
                try? await Task.sleep(nanoseconds: UInt64(initialDelay) * GameView.oneSecond)
				repeat {
					for _ in 0..<3 {
						if self.initialDate == nil || gameState.wrappedValue != .playing || Task.isCancelled { return }
						SoundEffects.default.play(.warning)
                        try? await Task.sleep(nanoseconds: GameView.oneSecond)
					}
					if self.initialDate == nil || gameState.wrappedValue != .playing || Task.isCancelled { return }
					board.randomMove()
                    try? await Task.sleep(nanoseconds: UInt64(delayInSeconds) * GameView.oneSecond)
				} while self.initialDate != nil && gameState.wrappedValue == .playing && !Task.isCancelled
		   }
		} else {
			wrappedBoard
		}
	}

	var displayTime: String {
		guard let initialDate = initialDate else {
			if game.accumulatedTime > 0 {
				let intTime = Int(game.accumulatedTime)
				return "\(intTime / 60):\(seconds: intTime % 60)"
			}
			return "0:00"
		}
		let currentGameTime = game.accumulatedTime + Date().timeIntervalSinceReferenceDate - initialDate.timeIntervalSinceReferenceDate
		let intTime = gameState == .playing ? Int(currentGameTime) : Int(game.accumulatedTime)
		return "\(intTime / 60):\(seconds: intTime % 60)"
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
						initialDate = Date()
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
			initialDate = nil
			for index in 0..<game.tiles.count {
				game.tiles[index].renderState = .fading
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + GameView.gameFadeDuration) {
				gameState = .new
				game.startNewGame()
				PuzzleImages.currentImage = PuzzleImages.randomFavorite()
				DispatchQueue.main.async {
					startNew()
				}
			}
		} else {
			initialDate = Date()
		}
	}

	@Sendable func finishGame() async {
		DispatchQueue.main.async {
			SoundEffects.default.play(.gameWin)
			for index in 0..<game.tiles.count {
				game.tiles[index].renderState = .lifted(falling: false)
			}
		}
		let totalDuration = Double(game.tiles.count) / 2.0
		await withTaskGroup(of: Int.self) { group -> Void in
			for index in 0..<game.tiles.count {
				group.addTask {
					let delay = Double.random(in: 1.0..<totalDuration)
                    try? await Task.sleep(nanoseconds: UInt64(delay) * GameView.oneSecond)
					return index
				}
			}
			for await index in group {
				guard !Task.isCancelled else { break }
				DispatchQueue.main.async {
					SoundEffects.default.play(.click)
					game.tiles[index].renderState = .lifted(falling: true)
				}
			}
		}
		// TODO: Fix the dialog freezing the game
//		guard !Task.isCancelled else { return }
//		showingWinGameDialog = true
	}
}

fileprivate extension String.StringInterpolation {

	mutating func appendInterpolation(seconds value: Int) {

		let formatter = NumberFormatter()
		formatter.positiveFormat = "00"
		formatter.formatWidth = 2
		if let result = formatter.string(from: value as NSNumber) {
			appendLiteral(result)
		}
	}
}

struct GameView_Previews: PreviewProvider {

	static let game = Game(rows: 6, columns: 4, mode: .swap)
	@State static var gameState: GameView.GameState = .new
	@State static var presenterVisible = false
	
    static var previews: some View {
		GameView(game: game, gameState: $gameState, presenterVisible: $presenterVisible, randomJumps: false)
    }
}
