//
//  GameType.swift
//  daves-tiles
//
//  Created by The App Studio LLC on 2/11/24.
//  Copyright © 2024 The App Studio LLC.
//

import SwiftUI

struct GameType: Equatable {
   let mode: Game.Mode
   let randomJumps: Bool
}

extension GameType {

	static var initial = GameType(mode: .classic, randomJumps: false)

	var localizedText: String {
		switch (mode, randomJumps) {
		case (.classic, false): return String(localized: "classic", comment: "The name of classic mode")
		case (.classic, true): return String(localized: "nightmare", comment: "The name of nightmare mode")
		case (.swap, false): return String(localized: "swap", comment: "The name of swap mode")
		case (.swap, true): return String(localized: "surprise", comment: "The name of surprise mode")
		}
	}
}
