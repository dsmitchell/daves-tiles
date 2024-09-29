//
//  GamePicker.swift
//  daves-tiles
//
//  Created by David Mitchell on 3/23/24.
//

import SwiftUI

struct GamePicker: View {
	
	@Binding var selectedGameId: Game.ID?

	let gameSelections: [GameSelection]
	let gameType: GameType
	let startRotation = Date.timeIntervalSinceReferenceDate

	var body: some View {
		
		TabView(selection: $selectedGameId) {
			ForEach(gameSelections, id: \.game.id) { gameSelection in
				VStack {
#if os(visionOS)
					boardView(for: gameSelection.game)
						.scaleEffect(0.66)
					NavigationLink(value: gameSelection) {
						Text("Play Game", comment: "Start or continue a game from the main screen")
					}
#else
					NavigationLink(value: gameSelection) {
						boardView(for: gameSelection.game)
							.scaleEffect(0.66)
					}
					Spacer(minLength: 40)
#endif
				}
				.tabItem {
					Label(gameSelection.difficulty.displayValue, systemImage: gameSelection.difficulty.tabImageResourceName)
				}
				.tag(gameSelection.game.id)
			}
		}
    }
	
	@ViewBuilder func boardView(for game: Game) -> some View {
		TimelineView(.animation(paused: false)) { context in
			let rotation = context.date.timeIntervalSinceReferenceDate - startRotation
			let showSwap = gameType.randomJumps && Int(floor(rotation)) % 4 < 2
			let swaps = gameType.randomJumps ? BoardView.SwapInfo(indices: swaps(for: game), enabled: showSwap) : BoardView.SwapInfo(indices: [], enabled: false)
			
			BoardView(game: game, swaps: swaps)
				.rotation3DEffect(.degrees(2.6 * cos(rotation)), axis: (x: 1, y: 0, z: 0))
				.rotation3DEffect(.degrees(4.0 * sin(rotation)), axis: (x: 0, y: 1, z: 0))
				.rotation3DEffect(.degrees(tan(rotation / 10.0)), axis: (x: 0, y: -1, z: 0))
#if !os(visionOS)
				.rotation3DEffect(.degrees(15), axis: (x: 1.01333332, y: 1, z: 0.37))
#endif
#if os(visionOS)
				.offset(z: 50 + 78 * (1 - cos(rotation / 5.0)))
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

fileprivate extension GameDifficulty {
	var tabImageResourceName: String {
		switch self {
		case .easy: return "square.grid.2x2.fill"
		case .medium: return "square.grid.3x3.fill"
		case .hard: return "square.grid.4x3.fill"
		}
	}
}

#Preview {
	@Previewable @State var selectedGameId: Game.ID?
	let gameSelections: [GameSelection] = []
	let gameType: GameType = .initial

	return GamePicker(selectedGameId: $selectedGameId, gameSelections: gameSelections, gameType: gameType)
}
