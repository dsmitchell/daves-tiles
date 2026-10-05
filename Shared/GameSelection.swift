//
//  GameSelection.swift
//  daves-tiles
//
//  Created by David Mitchell on 3/25/24.
//

struct GameSelection {
	var game: Game
	var difficulty: GameDifficulty
}

extension GameSelection: Hashable {
	
	static func == (lhs: GameSelection, rhs: GameSelection) -> Bool {
		lhs.game.id == rhs.game.id
	}
	
	func hash(into hasher: inout Hasher) {
		hasher.combine(game.id)
	}
}
