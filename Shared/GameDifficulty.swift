//
//  GameDifficulty.swift
//  daves-tiles
//
//  Created by The App Studio LLC on 2/11/24.
//  Copyright © 2024 The App Studio LLC.
//

import SwiftUI

enum GameDifficulty: String, Codable, CaseIterable {
	case easy
	case medium
	case hard
}

extension GameDifficulty {

	var displayValue: String {
		switch self {
		case .easy: return String(localized: "Easy", comment: "The Easy game board")
		case .medium: return String(localized: "Medium", comment: "The Medium game board")
		case .hard: return String(localized: "Hard", comment: "The Hard game board")
		}
	}
	
	var systemImage: String {
		switch self {
		case .easy: return "square.grid.2x2.fill"
		case .medium: return "square.grid.3x3.fill"
		case .hard: return "square.grid.4x3.fill"
		}
	}
	
	var grid: (rows: Int, columns: Int) {
		switch self {
		case .easy: return (rows: 5, columns: 3)
		case .medium: return (rows: 7, columns: 4)
		case .hard: return (rows: 8, columns: 5)
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
