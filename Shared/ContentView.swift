//
//  ContentView.swift
//  daves-tiles
//
//  Created by The App Studio LLC on 6/14/21.
//  Copyright © 2021 The App Studio LLC.
//

import SwiftUI

struct ContentView: View {

	struct GameSelection {
		var game: Game
		var state: GameView.GameState
		var difficulty: GameDifficulty
	}

	@State var gameSelections: [GameSelection] = ContentView.initialSelections
	@State var pickerVisible = false
	@State var gameSelection: GameDifficulty = .easy
	@State var score = 0
	@State var gameType: GameType = .initial
	@State private var path: [Color] = [] // Nothing on the stack by default.

	func setMode(_ mode: Game.Mode, randomJumps: Bool) {
		gameType = GameType(mode: mode, randomJumps: randomJumps)
		for difficulty in GameDifficulty.allCases {
			gameSelections[difficulty.tabIndex] = ContentView.gameSelection(for: difficulty, mode: mode, randomJumps: randomJumps)
		}
	}
	
	let startRotation = Date.timeIntervalSinceReferenceDate

    var body: some View {

		NavigationStack(path: $path) {
			TabView(selection: $gameSelection) {
				ForEach($gameSelections, id: \.game.id) { gameSelection in
					let difficulty = gameSelection.difficulty.wrappedValue
					VStack {
						let game = gameSelection.game.wrappedValue
						let state = gameSelection.state
#if os(visionOS)
						boardView(for: game, state: state)
							.scaleEffect(0.8)
						Spacer()
						NavigationLink(destination: GameView(game: game, gameState: state, presenterVisible: $pickerVisible, randomJumps: gameType.randomJumps)) {
							Text("Play Game", comment: "Start or continue a game from the main screen")
						}
#else
						NavigationLink(destination: GameView(game: game, gameState: state, presenterVisible: $pickerVisible, randomJumps: gameType.randomJumps)) {
							boardView(for: game, state: state)
						}
						.scaleEffect(0.7)
#endif
						Spacer(minLength: 40)
					}
					.tabItem {
						Label(difficulty.displayValue, systemImage: difficulty.tabImageResourceName)
					}
					.tag(difficulty)
				}
			}
#if os(visionOS)
			.ornament(attachmentAnchor: .scene(.top)) {
				HStack {
					gameSelectionButtons()
				}
				.padding(12)
				.glassBackgroundEffect()
			}
#endif
			.toolbar {
#if os(macOS)
				let placement: ToolbarItemPlacement = .principal
#else
				let placement: ToolbarItemPlacement = .navigationBarLeading
#endif
				ToolbarItemGroup(placement: placement) {
					HStack(alignment: .lastTextBaseline) {
						Text("Dave's Tiles", comment: "The title of the application")
							.font(.system(.largeTitle, design: .rounded))
							.allowsTightening(true)
							.minimumScaleFactor(0.5)
#if os(visionOS)
						Text(self.gameType.localizedText)
#else
						Menu {
							gameSelectionButtons()
						} label: {
							Text(self.gameType.localizedText)
						}
#endif
					}
					.animation(nil, value: gameType)
				}
			}
			.onAppear {
				pickerVisible = true // This can occur right after successful presentation of the NavigationLink
				if gameSelections[gameSelection.tabIndex].state == .finished {
					gameSelections[gameSelection.tabIndex] = ContentView.gameSelection(for: gameSelection, mode: gameType.mode, randomJumps: gameType.randomJumps)
					PuzzleImages.currentImage = PuzzleImages.randomFavorite()
				}
			}
			.onDisappear {
				pickerVisible = false
			}
		}
#if !os(macOS)
		.navigationViewStyle(StackNavigationViewStyle())
#endif
		.onAppear {
			SoundEffects.default.preloadSounds()
		}
}
	
	@ViewBuilder func gameSelectionButtons() -> some View {
		Button(action: { setMode(.swap, randomJumps: false) }) {
			Text(GameType(mode: .swap, randomJumps: false).localizedText.localizedCapitalized)
		}
		Button(action: { setMode(.swap, randomJumps: true) }) {
			Text(GameType(mode: .swap, randomJumps: true).localizedText.localizedCapitalized)
		}
		Button(action: { setMode(.classic, randomJumps: false) }) {
			Text(GameType(mode: .classic, randomJumps: false).localizedText.localizedCapitalized)
		}
		Button(action: { setMode(.classic, randomJumps: true) }) {
			Text(GameType(mode: .classic, randomJumps: true).localizedText.localizedCapitalized)
		}
	}

	@ViewBuilder func boardView(for game: Game, state: Binding<GameView.GameState>) -> some View {
		TimelineView(.animation) { context in
			let rotation = context.date.timeIntervalSinceReferenceDate - startRotation
			let showSwap = gameType.randomJumps && Int(floor(rotation)) % 4 < 2
			let swaps = gameType.randomJumps ? BoardView.SwapInfo(indices: swaps(for: game), enabled: showSwap) : BoardView.SwapInfo(indices: [], enabled: false)
			
			BoardView(game: game, gameState: state, swaps: swaps)
				.rotation3DEffect(.degrees(2.6 * cos(rotation)), axis: (x: 1, y: 0, z: 0))
				.rotation3DEffect(.degrees(4.0 * sin(rotation)), axis: (x: 0, y: 1, z: 0))
				.rotation3DEffect(.degrees(tan(rotation / 10.0)), axis: (x: 0, y: -1, z: 0))
#if os(visionOS)
				.offset(z: 50 + 78 * (1 - cos(rotation / 5.0)))
#else
				.rotation3DEffect(.degrees(15), axis: (x: 1.01333332, y: 1, z: 0.37))
#endif
		}
	}

	func swaps(for game: Game) -> [Int] {
		if let openTileId = game.openTileId, let openTileIndex = game.tiles.firstIndex(where: { $0.id == openTileId }) {
			return [openTileIndex, (openTileIndex + game.tiles.count / 3) % game.tiles.count]
		}
		let iterations = min(game.columns, game.rows)
		return (0..<iterations).map { iteration in
			(iteration * 2 + iteration * game.columns + game.tiles.count / iterations) % game.tiles.count
		}
	}
}

fileprivate extension ContentView {

	static var initialSelections: [GameSelection] {
		return GameDifficulty.allCases.map { difficulty in
			ContentView.gameSelection(for: difficulty, mode: GameType.initial.mode, randomJumps: GameType.initial.randomJumps)
		}
	}

	static func gameSelection(for difficulty: GameDifficulty, mode: Game.Mode, randomJumps: Bool) -> GameSelection {
		let grid = difficulty.grid
		let game = Game(rows: grid.rows, columns: grid.columns, mode: mode)
		return GameSelection(game: game, state: .new, difficulty: difficulty)
	}
}

fileprivate extension GameDifficulty {

	var tabImageResourceName: String {
		switch self {
		case .easy: return "square.grid.2x2.fill"
		case .medium: return "square.grid.3x3.fill"
		case .hard: return "square.grid.4x3.fill"
		}
	}

	var tabIndex: Int {
		switch self {
		case .easy: return 0
		case .medium: return 1
		case .hard: return 2
		}
	}
}

#Preview {
	ContentView()
}
