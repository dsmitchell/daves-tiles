//
//  ContentView.swift
//  Shared
//
//  Created by The App Studio LLC on 6/14/21.
//

import SwiftUI
import CoreData

struct ContentView: View {

    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
		NavigationView {
			GamePickerView()
		}
		.navigationViewStyle(StackNavigationViewStyle())
		.onAppear {
			SoundEffects.default.preloadSounds()
		}
    }
}

struct GamePickerView: View {

	enum GameDifficulty: Hashable, CaseIterable {
		case easy
		case medium
		case hard
	}

	struct GameSelection {
		var game: Game
		var state: GameView.GameState
		var difficulty: GameDifficulty
	}

	struct GameType: Equatable {
		let mode: Game.Mode
		let randomJumps: Bool
	}

	@State var gameSelections: [GameSelection] = GamePickerView.initialSelections
	@State var pickerVisible = false
	@State var gameSelection: GameDifficulty = .easy
	@State var score = 0
	@State private var gameType: GameType = GameType(mode: GamePickerView.initialGameType.mode, randomJumps: GamePickerView.initialGameType.randomJumps)

	func setMode(_ mode: Game.Mode, randomJumps: Bool) {
		gameType = GameType(mode: mode, randomJumps: randomJumps)
		for difficulty in GameDifficulty.allCases {
			gameSelections[difficulty.tabIndex] = GamePickerView.gameSelection(for: difficulty, mode: mode, randomJumps: randomJumps)
		}
	}

	var body: some View {
		TimelineView(.animation) { context in
			let rotation = Double(context.date.timeIntervalSinceReferenceDate)
			let showSwap = gameType.randomJumps && Int(floor(context.date.timeIntervalSinceReferenceDate)) % 4 < 2
			TabView(selection: $gameSelection) {
				ForEach($gameSelections, id: \.game.id) { gameSelection in
					let difficulty = gameSelection.difficulty.wrappedValue
					VStack {
						pickerView(for: gameSelection.game.wrappedValue, state: gameSelection.state, with: rotation, showSwap: showSwap)
						Spacer(minLength: 40)
					}
					.tabItem {
						Label(difficulty.displayValue, systemImage: difficulty.imageResourceName)
					}
					.tag(difficulty)
				}
			}
		}
		.toolbar {
			ToolbarItemGroup(placement: .navigationBarLeading) {
				HStack(alignment: .lastTextBaseline) {
					Text("Dave's Tiles")
						.font(.system(.largeTitle, design: .rounded))
					Menu {
						Button(action: { setMode(.swap, randomJumps: false) }) {
							Text(GameType(mode:.swap, randomJumps: false).buttonText.localizedCapitalized)
						}
						Button(action: { setMode(.swap, randomJumps: true) }) {
							Text(GameType(mode:.swap, randomJumps: true).buttonText.localizedCapitalized)
						}
						Button(action: { setMode(.classic, randomJumps: false) }) {
							Text(GameType(mode:.classic, randomJumps: false).buttonText.localizedCapitalized)
						}
						Button(action: { setMode(.classic, randomJumps: true) }) {
							Text(GameType(mode:.classic, randomJumps: true).buttonText.localizedCapitalized)
						}
					} label: {
						Text(self.gameType.buttonText)
					}
				}
				.animation(nil, value: gameType)
			}
		}
		.onAppear {
			pickerVisible = true // This can occur right after successful presentation of the NavigationLink
			if gameSelections[gameSelection.tabIndex].state == .finished {
				gameSelections[gameSelection.tabIndex] = GamePickerView.gameSelection(for: gameSelection, mode: gameType.mode, randomJumps: gameType.randomJumps)
			}
		}
		.onDisappear {
			pickerVisible = false
		}
	}

	@ViewBuilder func pickerView(for game: Game, state: Binding<GameView.GameState>, with rotation: Double, showSwap: Bool) -> some View {
		NavigationLink(destination: GameView(game: game, gameState: state, presenterVisible: $pickerVisible, randomJumps: gameType.randomJumps)) {
			let swaps = gameType.randomJumps ? BoardView.SwapInfo(indices: swaps(for: game), enabled: showSwap) : BoardView.SwapInfo(indices: [], enabled: false)
			BoardView(game: game, gameState: state, swaps: swaps)
				.rotation3DEffect(.degrees(15), axis: (x: 1.01333332, y: 1, z: 0.37))
				.rotation3DEffect(.degrees(2.6 * cos(rotation)), axis: (x: 1, y: 0, z: 0))
				.rotation3DEffect(.degrees(4.0 * sin(rotation)), axis: (x: 0, y: 1, z: 0))
				.rotation3DEffect(.degrees(tan(rotation / 10.0)), axis: (x: 0, y: -1, z: 0))
		}
		.scaleEffect(0.7)
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

fileprivate extension GamePickerView {

	static var initialGameType = GameType(mode: .classic, randomJumps: false)

	static var initialSelections: [GameSelection] {
		return GameDifficulty.allCases.map { difficulty in
			GamePickerView.gameSelection(for: difficulty, mode: initialGameType.mode, randomJumps: initialGameType.randomJumps)
		}
	}

	static func gameSelection(for difficulty: GameDifficulty, mode: Game.Mode, randomJumps: Bool) -> GameSelection {
		let grid = difficulty.grid
		let game = Game(rows: grid.rows, columns: grid.columns, mode: mode)
		return GameSelection(game: game, state: .new, difficulty: difficulty)
	}
}

fileprivate extension GamePickerView.GameDifficulty {

	var displayValue: String {
		switch self {
		case .easy: return "Easy"
		case .medium: return "Medium"
		case .hard: return "Hard"
		}
	}

	var grid: (rows: Int, columns: Int) {
		switch self {
		case .easy: return (rows: 5, columns: 3)
		case .medium: return (rows: 7, columns: 4)
		case .hard: return (rows: 8, columns: 5)
		}
	}

	var imageResourceName: String {
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

fileprivate extension GamePickerView.GameType {

	var buttonText: String {
		switch (mode, randomJumps) {
		case (.classic, false): return "classic"
		case (.classic, true): return "nightmare"
		case (.swap, false): return "swap"
		case (.swap, true): return "surprise"
		}
	}
}

struct ContentView_Previews: PreviewProvider {

    static var previews: some View {
        ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
