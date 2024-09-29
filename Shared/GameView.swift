//
//  GameView.swift
//  daves-tiles
//
//  Created by The App Studio LLC on 7/7/21.
//  Copyright © 2021 The App Studio LLC.
//

import SwiftUI

struct GameView: View {

#if os(visionOS)
	static let gameFadeDuration = BoardView.standardDuration * 4
#else
	static let gameFadeDuration = BoardView.standardDuration
#endif
	static let oneSecond = UInt64(1_000_000_000)

	@ObservedObject var game: Game
	@Binding var gameState: GameState
	@Binding var presenterVisible: Bool
	@State private var initialDate: Date? {
		didSet { stopTimer = false }
	}
	@State private var finishGameTask: Task<Void,Never>?
	@State private var showingWinGameDialog = false
	@State private var stopTimer = false
	
	let randomJumps: Bool
	let playAgain = String(localized: "Play again", comment: "Prompts the player to play again after winning")
	let cancel = String(localized: "Cancel", comment: "Dismisses the congratulations without starting a new game")
	let restart = String(localized: "New Game", comment: "Allows the player to cancel the current game and start a new game")

	enum GameState {
		case new		// Tiles are off-screen at the bottom
		case playing	// Normal game-play state
		case finished	// Game is finished
	}

	var body: some View {

		let congrats = String(localized: "Congratulations! You won with a time of \(displayTime) in \(game.moves) moves", comment: "The congratulatory phrase when the player has won")

		let board = withChangeObservers(boardView(gameState: $gameState))
#if !os(visionOS)
			.ignoresSafeArea(.container, edges: .bottom)
#endif
			.padding(4)
			.alert(congrats, isPresented: $showingWinGameDialog) {
				Button(playAgain, action: newGame)
				Button(cancel, role: .cancel) { }
			}
#if !os(macOS)
			.navigationBarTitleDisplayMode(.inline)
#endif
			.toolbar {
				ToolbarItemGroup(placement: .principal) {
					if let initialDate = initialDate, gameState == .playing {
						TimelineView(.periodic(from: initialDate, by: 1.0)) { context in
							Text("Moves: \(game.moves) Time: \(displayTime)", comment: "The elapsed time and number of moves currently made")
								.allowsTightening(true)
								.minimumScaleFactor(0.5)
						}
					} else {
						Text("Moves: \(game.moves) Time: \(displayTime)", comment: "The elapsed time and number of moves currently made")
							.allowsTightening(true)
							.minimumScaleFactor(0.5)
					}
				}
#if os(macOS)
				let placement: ToolbarItemPlacement = .secondaryAction
#else
				let placement: ToolbarItemPlacement = .navigationBarTrailing
#endif
				ToolbarItemGroup(placement: placement) {
					Button(action: newGame) {
						Label(restart, systemImage: "arrow.clockwise.circle")
					}
					.disabled([.new].contains(gameState))
				}
			}

#if os(visionOS)
		VStack {
			board
				.offset(z: 16)
			Spacer(minLength: 20)
		}
#else
		board
#endif
	}
	
	func presenterVisibleChanged(_: Bool, _ newValue: Bool) {
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
		Task { await newGame(firstAppearance: true) }
	}
	
	func gameStateChanged(_: GameState, _ newValue: GameState) {
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
	
	@ViewBuilder func withChangeObservers(_ view: some View) -> some View {
		if #available(iOS 17, macOS 14, *) {
			view
				.onChange(of: presenterVisible, presenterVisibleChanged)
				.onChange(of: gameState, gameStateChanged)
		} else {
			view // The old values do not matter -- just pass in fake values
				.onChange(of: presenterVisible) { presenterVisibleChanged(false, $0) }
				.onChange(of: gameState) { gameStateChanged(.finished, $0) }
		}
	}

	@ViewBuilder func boardView(gameState: Binding<GameState>) -> some View {
		let board = BoardView(game: game, gameState: gameState)
		if let initialDate = initialDate, gameState.wrappedValue == .playing {
			board.task {
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
				while !stopTimer && gameState.wrappedValue == .playing && !Task.isCancelled {
					for _ in 0..<3 {
						SoundEffects.default.play(.warning)
						try? await Task.sleep(nanoseconds: GameView.oneSecond)
						if stopTimer || gameState.wrappedValue != .playing || Task.isCancelled { return }
					}
					Task { await board.randomMove() }
					try? await Task.sleep(nanoseconds: UInt64(delayInSeconds) * GameView.oneSecond)
				}
			}
		} else {
			board
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
		// TODO: Decide whether we need or want a new `Game` instance (might be important for saving)
		Task { await newGame(firstAppearance: false) }
	}
	
	func animateTileEntry() async {
		SoundEffects.default.play(.newGame)
#if os(visionOS)
		let interval = 3.0 * Double(GameView.oneSecond) / Double(game.tiles.count)
#else
		let interval = Double(GameView.oneSecond) / Double(game.tiles.count)
#endif
		// TODO: Change the order based on portrait vs. landscape
		let animationOrder = 0..<game.tiles.count
		for index in animationOrder {
			try? await Task.sleep(nanoseconds: UInt64(interval))
			game.tiles[index].renderState = .none
		}
		try? await Task.sleep(nanoseconds: GameView.oneSecond)
		gameState = .playing
		initialDate = Date()
	}

	func newGame(firstAppearance: Bool) async {
		if gameState == .new, firstAppearance {
			game.startNewGame()
			await animateTileEntry()
		} else if !firstAppearance {
			stopTimer = true
			for index in 0..<game.tiles.count {
				game.tiles[index].renderState = .fading(wasFalling: gameState == .finished)
			}
			try? await Task.sleep(nanoseconds: UInt64(Double(GameView.oneSecond) * GameView.gameFadeDuration))
			gameState = .new
			game.startNewGame()
			PuzzleImages.currentImage = PuzzleImages.randomFavorite()
			await animateTileEntry()
		} else {
			initialDate = Date()
		}
	}

	@Sendable func finishGame() async {
		SoundEffects.default.play(.gameWin)
		try? await Task.sleep(nanoseconds: GameView.oneSecond)
		let animationOrder = (0..<game.tiles.count).shuffled()
		for index in animationOrder {
			guard !Task.isCancelled, !stopTimer else { break }
			let delay = Double.random(in: 0.05..<0.75) * Double(GameView.oneSecond)
			try? await Task.sleep(nanoseconds: UInt64(delay))
			SoundEffects.default.play(.click)
			game.tiles[index].renderState = .falling
		}
		guard !Task.isCancelled, !stopTimer else { return }
		try? await Task.sleep(nanoseconds: GameView.oneSecond)
		// This behavior is better with the NavigationStack, but can still "freeze" the app
		guard !Task.isCancelled else { return }
		showingWinGameDialog = true
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

#Preview {
	let game = Game(rows: 6, columns: 4, mode: .swap)
	@State var gameState: GameView.GameState = .finished
	@State var presenterVisible = false

	return GameView(game: game, gameState: $gameState, presenterVisible: $presenterVisible, randomJumps: false)
}
