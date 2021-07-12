//
//  GameView.swift
//  davestiles
//
//  Created by The App Studio LLC on 7/7/21.
//

import SwiftUI

struct GameView: View {

	@ObservedObject var game: Game

    var body: some View {
		VStack {
			BoardView(game: game)
				.padding()
//				.drawingGroup() // Must be after padding to avoid clipping // This is known to cause animation issues
//				.rotation3DEffect(.degrees(25), axis: (x: 0.25, y: 0.25, z: 0.25))
//				.frame(maxWidth: 600)
			Text("Moves: \(game.moves)")
				.animation(nil)
		}
		.navigationTitle("Dave's Tiles")
    }
}

struct GameView_Previews: PreviewProvider {

	static let game = Game(rows: 6, columns: 4)
	
    static var previews: some View {
		GameView(game: game)
    }
}
