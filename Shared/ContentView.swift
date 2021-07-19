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
		.navigationViewStyle(.stack)
		.onAppear {
			SoundEffects.default.preloadSounds()
		}
    }
}

struct GamePickerView: View {

	@StateObject var game = Game(rows: 5, columns: 3)

	var body: some View {
//		TimelineView(.animation) { context in
			NavigationLink(destination: GameView(game: game)) {
				Text("Play Game")
//				BoardView(game: game)
			}
//		}
		.navigationTitle("Dave's Tiles")
	}
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
