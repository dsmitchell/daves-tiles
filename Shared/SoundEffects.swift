//
//  SoundEffects.swift
//  daves-tiles
//
//  Created by The App Studio LLC on 7/13/21.
//  Copyright © 2021 The App Studio LLC.
//

import Foundation
import AVFoundation

public class SoundEffects {

	static let `default` = SoundEffects()

	public enum Effect: CaseIterable {
		case click
		case gameWin
		case jump
		case newGame
		case popDown
		case popUp
		case slide
		case warning
	}

	struct PlayerCollection {
		let players: [AVAudioPlayer]
		var nextPlayer = 0
	}

	var sounds = [Effect : PlayerCollection]()

	public init() {
		try! AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.ambient)
		try! AVAudioSession.sharedInstance().setActive(true)
	}

	public func preloadSounds() {
		sounds.reserveCapacity(Effect.allCases.count)
		for effect in Effect.allCases {
			switch effect {
			case .click:
				sounds[effect] = PlayerCollection(players: loadSound(named: effect.resourceName, count: 4))
			case .slide:
				sounds[effect] = PlayerCollection(players: loadSound(named: effect.resourceName, count: 4))
			default:
				sounds[effect] = PlayerCollection(players: loadSound(named: effect.resourceName))
			}
		}
	}

	private func loadSound(named name: String, count: Int = 1) -> [AVAudioPlayer] {
		guard let soundFileURL = Bundle.main.url(forResource: name, withExtension: "caf") else {
			fatalError("\(name).caf not found")
		}
		return (0..<count).map { _ in
			let player = try! AVAudioPlayer(contentsOf: soundFileURL)
			player.prepareToPlay()
			return player
		}
	}

	public func play(_ effect: Effect) {
		guard var playerCollection = sounds[effect] else { fatalError() }
		let nextPlayer = playerCollection.players[playerCollection.nextPlayer]
		playerCollection.nextPlayer = (playerCollection.nextPlayer + 1) % playerCollection.players.count
		sounds[effect] = playerCollection
		DispatchQueue.global().async {
			nextPlayer.play()
		}
	}
}

fileprivate extension SoundEffects.Effect {

	var resourceName: String {
		switch self {
		case .click: return "Click"
		case .gameWin: return "GameWin1"
		case .jump: return "Jump1"
		case .newGame: return "NewGame1"
		case .popDown: return "Popdown"
		case .popUp: return "Popup"
		case .slide: return "Slide1"
		case .warning: return "Warning1"
		}
	}
}
