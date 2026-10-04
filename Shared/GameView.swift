//
//  GameView.swift
//  daves-tiles
//
//  Created by The App Studio LLC on 7/7/21.
//  Copyright © 2021 The App Studio LLC.
//

import SwiftUI

struct GameView: View {

	@Environment(\.dismiss) private var dismiss
	@Environment(\.scenePhase) private var scenePhase

	static let gameFadeDuration = BoardView.standardDuration * 4
	static let oneSecond = UInt64(1_000_000_000)

	var game: Game
		
	@Binding var presenterVisible: Bool
	@Binding var puzzleImage: PuzzleImage
	@State private var initialDate: Date? {
		didSet { stopTimer = false }
	}
	@State private var displayedGameSeconds = 0
	@State private var finishGameTask: Task<Void,Never>?
	@State private var showingWinGameDialog = false
	@State private var stopTimer = false
	@State private var warningFlashOpacity = 0.0
	
	let randomJumps: Bool
	let playAgain = String(localized: "Play again", comment: "Prompts the player to play again after winning")
	let cancel = String(localized: "Cancel", comment: "Dismisses the congratulations without starting a new game")
	let restart = String(localized: "New Game", comment: "Allows the player to cancel the current game and start a new game")

	var body: some View {

		let congrats = String(localized: "Congratulations! You won with a time of \(displayTime) in \(game.moves) moves", comment: "The congratulatory phrase when the player has won")

		VStack(spacing: 0) {
			gameControls
			boardView()
				.modify { view in
					if #available(iOS 17, macOS 14, *) {
						view
							.onChange(of: presenterVisible, presenterVisibleChanged)
							.onChange(of: game.state, gameStateChanged)
							.onChange(of: scenePhase, scenePhaseChanged)
					} else {
						view // The old values do not matter -- just pass in fake values
							.onChange(of: presenterVisible) { presenterVisibleChanged(false, $0) }
							.onChange(of: game.state) { gameStateChanged(.finished, $0) }
							.onChange(of: scenePhase) { scenePhaseChanged(.inactive, $0) }
					}
				}
#if os(visionOS)
				.scenePadding()
				.padding3D(.back, 16)
#else
				.ignoresSafeArea(.container, edges: .bottom)
				.padding(4)
#endif
				.alert(congrats, isPresented: $showingWinGameDialog) {
					Button(playAgain, action: newGame)
					Button(cancel, role: .cancel) { }
				}
				.toolbar(.hidden)
		}
		.opacity(boardOpacity(game.state))
		.animation(boardAnimation(game.state), value: game.state)
	}

	private var gameStatus: some View {
		Text("Moves: \(game.moves) Time: \(displayTime(seconds: gameStatusSeconds))", comment: "The elapsed time and number of moves currently made")
			.allowsTightening(true)
			.minimumScaleFactor(0.5)
			.lineLimit(1)
	}

	private var gameStatusSeconds: Int {
		initialDate == nil ? Int(game.accumulatedTime) : displayedGameSeconds
	}

	private var gameControls: some View {
		ZStack {
			gameStatus
				.padding(.horizontal, 44)

			HStack {
				Button(action: dismiss.callAsFunction) {
					Label("Back", systemImage: "chevron.backward")
						.labelStyle(.iconOnly)
				}
				.accessibilityHint("Returns to game selection")

				Spacer()

				Button(action: newGame) {
					Label(restart, systemImage: "arrow.clockwise.circle")
						.labelStyle(.iconOnly)
				}
				.disabled([.new].contains(game.state))
			}
		}
		.font(.body)
		.scenePadding([.top, .horizontal])
		.frame(minHeight: 36)
		.background(warningColor.opacity(warningFlashOpacity))
	}

	private var warningColor: Color {
		game.mode == .classic ? .red : .purple
	}
	
	func presenterVisibleChanged(_: Bool, _ newValue: Bool) {
		// This is the equivalent of viewDidAppear (because the presenter is now onDisappear)
		print("Presenter visible: \(newValue)")
		guard !presenterVisible else {
			if game.state == .playing, let initialDate = initialDate {
				game.accumulatedTime += Date().timeIntervalSinceReferenceDate - initialDate.timeIntervalSinceReferenceDate
			}
			initialDate = nil
			finishGameTask?.cancel()
			finishGameTask = nil
			return
		}
		Task { await newGame(firstAppearance: true) }
	}
	
	func gameStateChanged(_: Game.State, _ newValue: Game.State) {
		switch newValue {
		case .new where finishGameTask != nil:
			finishGameTask!.cancel()
			finishGameTask = nil
		case .finished where initialDate != nil:
			let now = Date()
			game.accumulatedTime += now.timeIntervalSinceReferenceDate - initialDate!.timeIntervalSinceReferenceDate
			displayedGameSeconds = Int(game.accumulatedTime)
			initialDate = nil
			finishGameTask = Task { await finishGame() }
		default: break
		}
	}

	func scenePhaseChanged(_: ScenePhase, _ newValue: ScenePhase) {
		if newValue == .background, game.state == .playing, let runningStartDate = initialDate {
			game.accumulatedTime += Date().timeIntervalSince(runningStartDate)
			initialDate = nil
		} else if newValue == .active, game.state == .playing, initialDate == nil, !presenterVisible {
			initialDate = Date()
		}
	}

	func boardView() -> some View {
		let board = BoardView(game: game, swaps: nil)
		return board
			.environment(\.puzzleImageIsPlaying, ![.new, .fading].contains(game.state))
			.task(id: initialDate) { @MainActor in
				guard let initialDate, game.state == .playing else { return }
				defer {
					print("Exiting game clock")
				}

				let currentGameSecond = Int(elapsedGameTime(at: Date(), since: initialDate))
				displayedGameSeconds = currentGameSecond

				let randomJumpDelay = game.openTileId == nil ? game.tiles.count - min(game.columns, game.rows) : game.tiles.count * 2
				var nextWarningSecond = randomJumps
					? ((currentGameSecond / randomJumpDelay) + 1) * randomJumpDelay
					: nil
				var warningsPlayed = 0
				var randomMoveSecond: Int?
				print("Starting game clock at game time \(currentGameSecond)s...")

				while !stopTimer && self.game.state == .playing && !Task.isCancelled {
					let nextGameSecond = Int(elapsedGameTime(at: Date(), since: initialDate)) + 1
					await sleep(untilGameTime: TimeInterval(nextGameSecond), since: initialDate)
					if stopTimer || self.game.state != .playing || Task.isCancelled { return }

					let elapsedSecond = Int(elapsedGameTime(at: Date(), since: initialDate))
					displayedGameSeconds = elapsedSecond

					if let scheduledMoveSecond = randomMoveSecond, elapsedSecond >= scheduledMoveSecond {
						Task { await board.randomMove() }
						warningsPlayed = 0
						nextWarningSecond = elapsedSecond + randomJumpDelay
						randomMoveSecond = nil
					} else if let scheduledWarningSecond = nextWarningSecond, elapsedSecond >= scheduledWarningSecond {
						playWarning()
						warningsPlayed += 1
						if warningsPlayed == 3 {
							randomMoveSecond = elapsedSecond + 1
							nextWarningSecond = nil
						} else {
							nextWarningSecond = elapsedSecond + 1
						}
					}
				}
			}
	}

	@MainActor private func sleep(untilGameTime target: TimeInterval, since initialDate: Date) async {
		let remainingTime = target - elapsedGameTime(at: Date(), since: initialDate)
		guard remainingTime > 0 else { return }
		try? await Task.sleep(nanoseconds: UInt64(remainingTime * Double(GameView.oneSecond)))
	}

	@MainActor private func playWarning() {
		SoundEffects.default.play(.warning)
		warningFlashOpacity = 1
		withAnimation(.linear(duration: 1)) {
			warningFlashOpacity = 0
		}
	}

	func boardAnimation(_ gameState: Game.State) -> Animation? {
		return gameState == .fading ? .linear(duration: GameView.gameFadeDuration) : nil
	}
	
	func boardOpacity(_ gameState: Game.State) -> Double {
		return gameState == .fading ? 0 : 1
	}

	var displayTime: String {
		displayTime(at: Date())
	}

	private func displayTime(at date: Date) -> String {
		guard let initialDate = initialDate else {
			return displayTime(seconds: Int(game.accumulatedTime))
		}
		let currentGameTime = elapsedGameTime(at: date, since: initialDate)
		let seconds = game.state == .playing ? Int(currentGameTime) : Int(game.accumulatedTime)
		return displayTime(seconds: seconds)
	}

	private func displayTime(seconds: Int) -> String {
		"\(seconds / 60):\(seconds: seconds % 60)"
	}

	private func elapsedGameTime(at date: Date, since initialDate: Date) -> TimeInterval {
		game.accumulatedTime + date.timeIntervalSince(initialDate)
	}

	func newGame() {
		// TODO: Decide whether we need or want a new `Game` instance (might be important for saving)
		Task { await newGame(firstAppearance: false) }
	}
	
	@MainActor func animateTileEntry() async {
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
		game.state = .playing
		initialDate = Date()
	}

	@MainActor func newGame(firstAppearance: Bool) async {
		if game.state == .new, firstAppearance {
			game.startNewGame(imageIsLandscape: puzzleImage.isLandscape)
			await animateTileEntry()
		} else if !firstAppearance {
			stopTimer = true
			game.state = .fading
			try? await Task.sleep(nanoseconds: UInt64(Double(GameView.oneSecond) * GameView.gameFadeDuration))
			displayedGameSeconds = 0
			puzzleImage = PuzzleImageLibrary.randomFavorite()
			game.startNewGame(imageIsLandscape: puzzleImage.isLandscape)
			// A second wait seems to correct an issue animating new tiles after a completed game
			try? await Task.sleep(nanoseconds: UInt64(Double(GameView.oneSecond) * GameView.gameFadeDuration))
			await animateTileEntry()
		} else {
			initialDate = Date()
		}
	}

	@MainActor func finishGame() async {
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

fileprivate extension View {
	
	func modify<T: View>(@ViewBuilder _ modifier: (Self) -> T) -> some View {
		return modifier(self)
	}
}

#Preview {
	@Previewable @State var presenterVisible = false
	@Previewable @State var puzzleImage = PuzzleImageLibrary.randomFavorite()
	let game = Game(rows: 6, columns: 4, mode: .swap, imageIsLandscape: puzzleImage.isLandscape)

	return GameView(
		game: game,
		presenterVisible: $presenterVisible,
		puzzleImage: $puzzleImage,
		randomJumps: false
	)
}
