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

	// TODO: We will have a list of games, each with a different game state
	struct GameSelection {
		var game: Game
		var state: GameView.GameState
	}

	@State var gameSelections: [GameSelection] = [
		GameSelection(game: Game(rows: 5, columns: 3), state: .new),
		GameSelection(game: Game(rows: 7, columns: 4), state: .new),
		GameSelection(game: Game(rows: 8, columns: 5), state: .new)
	]
	@State var pickerVisible = false

	var body: some View {
		if #available(iOS 15, *) {
			TimelineView(.animation) { context in
				let rotation = Double(context.date.timeIntervalSinceReferenceDate)
				TabView {
					ForEach($gameSelections, id: \.game.id) { gameSelection in
						pickerView(for: gameSelection.game.wrappedValue, state: gameSelection.state)
							.rotation3DEffect(.degrees(2.6 * cos(rotation)), axis: (x: 1, y: 0, z: 0))
							.rotation3DEffect(.degrees(4.0 * sin(rotation)), axis: (x: 0, y: 1, z: 0))
							.rotation3DEffect(.degrees(tan(rotation / 10.0)), axis: (x: 0, y: -1, z: 0))
					}
				}
				.tabViewStyle(.page)
			}
			.navigationTitle("Dave's Tiles")
			.onAppear {
				pickerVisible = true // This can occur right after successful presentation of the NavigationLink
			}
			.onDisappear {
				pickerVisible = false
			}
		} else {
			TabView {
				ForEach($gameSelections, id: \.game.id) { gameSelection in
					pickerView(for: gameSelection.game.wrappedValue, state: gameSelection.state)
						.tabItem {
							Text("\(gameSelection.game.wrappedValue.columns)x\(gameSelection.game.wrappedValue.rows)")
						}
				}
			}
//			.tabViewStyle(.page)
//			pickerView(for: gameSelections[0].game, state: $gameSelections[0].state)
			.navigationTitle("Dave's Tiles")
			.onAppear {
				pickerVisible = true // This can occur right after successful presentation of the NavigationLink
			}
			.onDisappear {
				pickerVisible = false
			}
		}
	}

	@ViewBuilder func pickerView(for game: Game, state: Binding<GameView.GameState>) -> some View {
		NavigationLink(destination: GameView(game: game, gameState: state, presenterVisible: $pickerVisible)) {
			BoardView(game: game, gameState: state, interactive: false)
				.scaleEffect(0.6)
				.rotation3DEffect(.degrees(15), axis: (x: 1.01333332, y: 1, z: 0.37))
		}
	}
}

struct ContentView_Previews: PreviewProvider {

    static var previews: some View {
        ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
