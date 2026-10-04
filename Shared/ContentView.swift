//
//  ContentView.swift
//  daves-tiles
//
//  Created by The App Studio LLC on 6/14/21.
//  Copyright © 2021 The App Studio LLC.
//

import SwiftUI

struct ContentView: View {

	private static let initialPuzzleImage = PuzzleImageLibrary.initialFavorite()

	@State var gameSelections: [GameSelection]
	@State var pickerVisible = false
	@State var selectedGameId: Game.ID?
	@State var gameType: GameType = .initial
	@State private var puzzleImage = ContentView.initialPuzzleImage

	init() {
		let selections = ContentView.initialSelections(
			imageIsLandscape: ContentView.initialPuzzleImage.isLandscape
		)
		_gameSelections = State(initialValue: selections)
		_selectedGameId = State(initialValue: selections[GameDifficulty.easy.tabIndex].game.id)
	}

	var body: some View {

		VStack {
			GamePicker(
				selectedGameId: $selectedGameId,
				gameSelections: gameSelections,
				gameType: gameType,
				onPuzzleImageAdded: selectPuzzleImage,
				onSelectRandomPuzzleImage: selectRandomPuzzleImage
			) {
				gamePickerHeader(titleFont: .title.bold())
			}
			.environment(\.puzzleImage, puzzleImage)
//			Spacer() // Consider removing this -- but keep in the code until I decide
		}
		.navigationDestination(for: GameSelection.self) { gameSelection in
			GameView(
				game: gameSelection.game,
				presenterVisible: $pickerVisible,
				puzzleImage: $puzzleImage,
				randomJumps: gameType.randomJumps
			)
			.environment(\.puzzleImage, puzzleImage)
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
			let placement: ToolbarItemPlacement = .principal
			ToolbarItemGroup(placement: placement) {
				gamePickerHeader(titleFont: .system(.largeTitle, design: .rounded))
			}
		}
		.onAppear {
			pickerVisible = true // This can occur right after successful presentation of the NavigationLink
			if selectedGameId == nil {
				selectedGameId = gameSelections[GameDifficulty.medium.tabIndex].game.id
			} else if let gameIndex = gameSelections.firstIndex(where: { $0.game.id == selectedGameId }), gameSelections[gameIndex].game.state == .finished {
				puzzleImage = PuzzleImageLibrary.randomFavorite()
				for difficulty in GameDifficulty.allCases {
					gameSelections[difficulty.tabIndex] = ContentView.gameSelection(
						for: difficulty,
						mode: gameType.mode,
						imageIsLandscape: puzzleImage.isLandscape
					)
				}
				selectedGameId = gameSelections[gameIndex].game.id
			}
		}
		.onDisappear {
			pickerVisible = false
		}
	}
		
	@ViewBuilder func gamePickerHeader(titleFont: Font) -> some View {
		HStack(alignment: .lastTextBaseline, spacing: 8) {
			Text("Dave's Tiles", comment: "The title of the application, which is a tile game based on the 18th century puzzle")
				.font(titleFont)
				.allowsTightening(true)
				.minimumScaleFactor(0.5)
				.lineLimit(1)
#if os(visionOS)
			Text(gameType.localizedText)
#else
			Menu {
				gameSelectionButtons()
			} label: {
				Text(gameType.localizedText)
			}
			.tint(.accentColor)
#endif
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

	func selectRandomPuzzleImage() {
		selectPuzzleImage(PuzzleImageLibrary.randomFavorite())
	}

	func selectPuzzleImage(_ image: PuzzleImage) {
		puzzleImage = image
		let gameIndex = gameSelections.firstIndex(where: { $0.game.id == selectedGameId }) ?? GameDifficulty.medium.tabIndex
		for difficulty in GameDifficulty.allCases {
			gameSelections[difficulty.tabIndex] = ContentView.gameSelection(for: difficulty, mode: gameType.mode, imageIsLandscape: image.isLandscape)
		}
		selectedGameId = gameSelections[gameIndex].game.id
	}

	func setMode(_ mode: Game.Mode, randomJumps: Bool) {
		gameType = GameType(mode: mode, randomJumps: randomJumps)
			let gameIndex = gameSelections.firstIndex(where: { $0.game.id == selectedGameId }) ?? GameDifficulty.medium.tabIndex
			for difficulty in GameDifficulty.allCases {
				gameSelections[difficulty.tabIndex] = ContentView.gameSelection(
					for: difficulty,
					mode: mode,
					imageIsLandscape: puzzleImage.isLandscape
				)
			}
		selectedGameId = gameSelections[gameIndex].game.id
	}
}

fileprivate extension ContentView {

	static func initialSelections(imageIsLandscape: Bool) -> [GameSelection] {
		return GameDifficulty.allCases.map { difficulty in
			ContentView.gameSelection(
				for: difficulty,
				mode: GameType.initial.mode,
				imageIsLandscape: imageIsLandscape
			)
		}
	}

	static func gameSelection(
		for difficulty: GameDifficulty,
		mode: Game.Mode,
		imageIsLandscape: Bool
	) -> GameSelection {
		let grid = difficulty.grid
		let game = Game(
			rows: grid.rows,
			columns: grid.columns,
			mode: mode,
			imageIsLandscape: imageIsLandscape
		)
		return GameSelection(game: game, difficulty: difficulty)
	}
}

#Preview {
	return ContentView()
}
