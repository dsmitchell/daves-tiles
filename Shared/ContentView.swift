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

	@State var gameSelections: [GameSelection] = GamePickerView.initialSelections
	@State var pickerVisible = false
	@State var gameSelection: GameDifficulty = .easy
	@State var score = 0
	@State private var mode: Game.Mode = GamePickerView.initialMode

	func setMode(_ mode: Game.Mode, randomJumps: Bool = false) {
		self.mode = mode
		for difficulty in GameDifficulty.allCases {
			gameSelections[difficulty.tabIndex] = GamePickerView.gameSelection(for: difficulty, mode: mode)
		}
	}

	var body: some View {
		TimelineView(.animation) { context in
			let rotation = Double(context.date.timeIntervalSinceReferenceDate)
			TabView(selection: $gameSelection) {
				ForEach($gameSelections, id: \.game.id) { gameSelection in
					let difficulty = gameSelection.difficulty.wrappedValue
					VStack {
						pickerView(for: gameSelection.game.wrappedValue, state: gameSelection.state, with: rotation)
							.scaleEffect(0.7)
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
						Button(action: { setMode(.swap) }) {
							Text("Swap")
						}
						Button(action: { setMode(.classic) }) {
							Text("Classic")
						}
					} label: {
						Text(self.mode.buttonText(false))
					}
				}
				.animation(nil, value: self.mode)
			}
		}
		.onAppear {
			pickerVisible = true // This can occur right after successful presentation of the NavigationLink
			if gameSelections[gameSelection.tabIndex].game.isFinished {
				gameSelections[gameSelection.tabIndex] = GamePickerView.gameSelection(for: gameSelection, mode: mode)
			}
		}
		.onDisappear {
			pickerVisible = false
		}
	}

	@ViewBuilder func pickerView(for game: Game, state: Binding<GameView.GameState>, with rotation: Double) -> some View {
		NavigationLink(destination: GameView(game: game, gameState: state, presenterVisible: $pickerVisible)) {
			BoardView(game: game, gameState: state, interactive: false)
				.rotation3DEffect(.degrees(15), axis: (x: 1.01333332, y: 1, z: 0.37))
				.rotation3DEffect(.degrees(2.6 * cos(rotation)), axis: (x: 1, y: 0, z: 0))
				.rotation3DEffect(.degrees(4.0 * sin(rotation)), axis: (x: 0, y: 1, z: 0))
				.rotation3DEffect(.degrees(tan(rotation / 10.0)), axis: (x: 0, y: -1, z: 0))
		}
	}
}

fileprivate extension Game.Mode {

	func buttonText(_ randomJumps: Bool) -> String {
		switch (self, randomJumps) {
		case (.classic, false): return "classic"
		case (.classic, true): return "nightmare"
		case (.swap, false): return "swap"
		case (.swap, true): return "surprise"
		}
	}
}

fileprivate extension GamePickerView {

	static var initialMode: Game.Mode = .classic

	static var initialSelections: [GameSelection] {
		return [
			GamePickerView.gameSelection(for: .easy, mode: initialMode),
			GamePickerView.gameSelection(for: .medium, mode: initialMode),
			GamePickerView.gameSelection(for: .hard, mode: initialMode)
		]
	}

	static func gameSelection(for difficulty: GameDifficulty, mode: Game.Mode) -> GameSelection {
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

struct ContentView_Previews: PreviewProvider {

    static var previews: some View {
        ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
