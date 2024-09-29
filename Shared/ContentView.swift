//
//  ContentView.swift
//  daves-tiles
//
//  Created by The App Studio LLC on 6/14/21.
//  Copyright © 2021 The App Studio LLC.
//

import SwiftUI

struct ContentView: View {

	@State var gameSelections: [GameSelection] = ContentView.initialSelections
	@State var pickerVisible = false
	@State var selectedGameId: Game.ID?
	@State var gameType: GameType = .initial

	var body: some View {

		VStack {
			GamePicker(selectedGameId: $selectedGameId, gameSelections: gameSelections, gameType: gameType)
			Spacer()
		}
		.navigationDestination(for: GameSelection.self) { gameSelection in
			GameView(game: gameSelection.game, presenterVisible: $pickerVisible, randomJumps: gameType.randomJumps)
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
			}
		}
		.onAppear {
			pickerVisible = true // This can occur right after successful presentation of the NavigationLink
			if selectedGameId == nil {
				selectedGameId = gameSelections[GameDifficulty.medium.tabIndex].game.id
			} else if let gameIndex = gameSelections.firstIndex(where: { $0.game.id == selectedGameId }), gameSelections[gameIndex].game.state == .finished {
				PuzzleImages.currentImage = PuzzleImages.randomFavorite()
				for difficulty in GameDifficulty.allCases {
					gameSelections[difficulty.tabIndex] = ContentView.gameSelection(for: difficulty, mode: gameType.mode)
				}
				selectedGameId = gameSelections[gameIndex].game.id
			}
		}
		.onDisappear {
			pickerVisible = false
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

	func setMode(_ mode: Game.Mode, randomJumps: Bool) {
		gameType = GameType(mode: mode, randomJumps: randomJumps)
		let gameIndex = gameSelections.firstIndex(where: { $0.game.id == selectedGameId }) ?? GameDifficulty.medium.tabIndex
		for difficulty in GameDifficulty.allCases {
			gameSelections[difficulty.tabIndex] = ContentView.gameSelection(for: difficulty, mode: mode)
		}
		selectedGameId = gameSelections[gameIndex].game.id
	}
}

fileprivate extension ContentView {

	static var initialSelections: [GameSelection] {
		return GameDifficulty.allCases.map { difficulty in
			ContentView.gameSelection(for: difficulty, mode: GameType.initial.mode)
		}
	}

	static func gameSelection(for difficulty: GameDifficulty, mode: Game.Mode) -> GameSelection {
		let grid = difficulty.grid
		let game = Game(rows: grid.rows, columns: grid.columns, mode: mode)
		return GameSelection(game: game, difficulty: difficulty)
	}
}

#Preview {
	return ContentView()
}
