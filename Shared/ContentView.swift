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

	@Environment(\.scenePhase) private var scenePhase
	@Environment(\.verticalSizeClass) private var verticalSizeClass
	@Binding private var navigationPath: [GameSelection]
	@State var gameSelections: [GameSelection]
	@State var pickerVisible = false
	@State var selectedGameId: Game.ID?
	@State var gameType: GameType = .initial
	@State private var puzzleImage = ContentView.initialPuzzleImage
	@State private var showsTileNumbers = true
	@State private var hasRestoredNavigation = false
	private let restoresPresentedGame: Bool

	@MainActor init(navigationPath: Binding<[GameSelection]>) {
		_navigationPath = navigationPath
		let savedSession = GameSessionStore.load()
		let restoredImage = savedSession.flatMap {
			PuzzleImageLibrary.image(id: $0.puzzleImageID)
		} ?? ContentView.initialPuzzleImage
		let restoredSelections = savedSession?.selections.compactMap {
			$0.restoredSelection()
		}
		let selections = restoredSelections?.count == GameDifficulty.allCases.count
			? restoredSelections!
			: ContentView.initialSelections(imageIsLandscape: restoredImage.isLandscape)
		let selectedDifficulty = savedSession?.selectedDifficulty ?? .easy

		_gameSelections = State(initialValue: selections)
		_selectedGameId = State(initialValue: selections[selectedDifficulty.tabIndex].game.id)
		_gameType = State(initialValue: savedSession.map {
			GameType(mode: $0.mode, randomJumps: $0.randomJumps)
		} ?? .initial)
		_puzzleImage = State(initialValue: restoredImage)
		_showsTileNumbers = State(initialValue: savedSession?.showsTileNumbers ?? true)
		restoresPresentedGame = savedSession?.presentsGame ?? false
	}

	var body: some View {

		VStack {
			GamePicker(
				selectedGameId: $selectedGameId,
				showsTileNumbers: $showsTileNumbers,
				gameSelections: gameSelections,
				gameType: gameType,
				onPuzzleImageAdded: selectPuzzleImage,
				onSelectRandomPuzzleImage: selectRandomPuzzleImage
			) {
				gamePickerHeader(titleFont: .title.bold())
			}
			.environment(\.puzzleImage, puzzleImage)
		}
		.navigationDestination(for: GameSelection.self) { gameSelection in
			GameView(
				game: gameSelection.game,
				presenterVisible: $pickerVisible,
				puzzleImage: $puzzleImage,
				randomJumps: gameType.randomJumps,
				showsTileNumbers: $showsTileNumbers
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
		.onAppear {
			let shouldRestorePresentedGame = !hasRestoredNavigation && restoresPresentedGame
			pickerVisible = true // This can occur right after successful presentation of the NavigationLink
			if !hasRestoredNavigation {
				hasRestoredNavigation = true
				if restoresPresentedGame,
				   navigationPath.isEmpty,
				   let selected = gameSelections.first(where: { $0.game.id == selectedGameId }) {
					navigationPath.append(selected)
				}
			}
			if selectedGameId == nil {
				selectedGameId = gameSelections[GameDifficulty.easy.tabIndex].game.id
			} else if !shouldRestorePresentedGame {
				preparePickerAfterCompletedGame()
			}
			updateUnstartedGamesForCurrentOrientation()
		}
		.onDisappear {
			pickerVisible = false
		}
		.onChange(of: scenePhase) { oldPhase, newPhase in
			if newPhase == .background, oldPhase != newPhase {
				persistSession()
			}
		}
		.onChange(of: verticalSizeClass) {
			updateUnstartedGamesForCurrentOrientation()
		}
		.onChange(of: navigationPath.map(\.game.id)) {
			if navigationPath.isEmpty {
				preparePickerAfterCompletedGame()
				updateUnstartedGamesForCurrentOrientation()
			}
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
		let gameIndex = gameSelections.firstIndex(where: { $0.game.id == selectedGameId })
		for difficulty in GameDifficulty.allCases {
			gameSelections[difficulty.tabIndex] = ContentView.gameSelection(
				for: difficulty,
				mode: gameType.mode,
				imageIsLandscape: gameLayoutIsLandscape(for: image)
			)
		}
		if let gameIndex = gameIndex {
			selectedGameId = gameSelections[gameIndex].game.id
		}
	}

	func setMode(_ mode: Game.Mode, randomJumps: Bool) {
		gameType = GameType(mode: mode, randomJumps: randomJumps)
		let gameIndex = gameSelections.firstIndex(where: { $0.game.id == selectedGameId })
		for difficulty in GameDifficulty.allCases {
			gameSelections[difficulty.tabIndex] = ContentView.gameSelection(
				for: difficulty,
				mode: mode,
				imageIsLandscape: gameLayoutIsLandscape(for: puzzleImage)
			)
		}
		if let gameIndex = gameIndex {
			selectedGameId = gameSelections[gameIndex].game.id
		}
	}

	func persistSession() {
		let selectedDifficulty = gameSelections.first(where: {
			$0.game.id == selectedGameId
		})?.difficulty ?? .easy
		GameSessionStore.save(
			SavedGameSession(
				puzzleImageID: puzzleImage.id,
				gameType: gameType,
				selectedDifficulty: selectedDifficulty,
				showsTileNumbers: showsTileNumbers,
				presentsGame: !navigationPath.isEmpty,
				gameSelections: gameSelections
			)
		)
	}

	private func preparePickerAfterCompletedGame() {
		guard let gameIndex = gameSelections.firstIndex(where: {
			$0.game.id == selectedGameId
		}), gameSelections[gameIndex].game.state == .finished else {
			return
		}

		puzzleImage = PuzzleImageLibrary.randomFavorite()
		for difficulty in GameDifficulty.allCases {
			gameSelections[difficulty.tabIndex] = ContentView.gameSelection(
				for: difficulty,
				mode: gameType.mode,
				imageIsLandscape: gameLayoutIsLandscape(for: puzzleImage)
			)
		}
		selectedGameId = gameSelections[gameIndex].game.id
	}

	private func gameLayoutIsLandscape(for image: PuzzleImage) -> Bool {
#if os(iOS)
		verticalSizeClass == .compact
#else
		image.isLandscape
#endif
	}

	private func updateUnstartedGamesForCurrentOrientation() {
		guard navigationPath.isEmpty else { return }
		let imageIsLandscape = gameLayoutIsLandscape(for: puzzleImage)
		for selection in gameSelections {
			selection.game.updateOpenTile(imageIsLandscape: imageIsLandscape)
		}
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
	@Previewable @State var navigationPath: [GameSelection] = []
	return NavigationStack(path: $navigationPath) {
		ContentView(navigationPath: $navigationPath)
	}
}
