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

	@StateObject var game = Game(rows: 5, columns: 3)

    var body: some View {
		NavigationView {
			GameView(game: game)
				.background(game.isFinished ? Color.yellow : Color.gray)
		}
		.navigationViewStyle(.stack)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
