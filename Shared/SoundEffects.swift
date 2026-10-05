//
//  SoundEffects.swift
//  daves-tiles
//
//  Created by The App Studio LLC on 7/13/21.
//  Copyright © 2021 The App Studio LLC.
//

import Foundation
@preconcurrency import AVFoundation

public final class SoundEffects: @unchecked Sendable {

	@MainActor static let `default` = SoundEffects()

	public enum Effect: CaseIterable, Sendable {
		case click
		case gameWin
		case jump
		case newGame
		case popDown
		case popUp
		case slide
		case warning
	}

	private struct VoiceCollection {
		let buffer: AVAudioPCMBuffer
		let voices: [AVAudioPlayerNode]
		var nextVoice = 0
	}

	private let audioEngine = AVAudioEngine()
	private let loadingQueue = DispatchQueue(label: "com.theappstudio.davestiles.audio-loading", qos: .userInitiated)
	private let stateLock = NSLock()
	private var isPreloading = false
	private var sounds = [Effect: VoiceCollection]()

	public init() {
		#if !os(macOS)
		try! AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.ambient)
		let audioSession = AVAudioSession.sharedInstance()
		if #available(iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *) {
			audioSession.activate { _, error in
				assert(error == nil, "Failed to activate the audio session: \(error!)")
			}
		} else {
			DispatchQueue.global(qos: .userInitiated).async {
				try! audioSession.setActive(true)
			}
		}
		#endif

		preloadSounds()
	}

	public func preloadSounds() {
		stateLock.lock()
		guard sounds.isEmpty, !isPreloading else {
			stateLock.unlock()
			return
		}
		isPreloading = true
		stateLock.unlock()

		loadingQueue.async { [self] in
			var loadedSounds = [Effect: VoiceCollection]()
			loadedSounds.reserveCapacity(Effect.allCases.count)

			for effect in Effect.allCases {
				let voiceCount = switch effect {
				case .click, .slide: 12
				case .warning: 4
				default: 2
				}
				loadedSounds[effect] = loadSound(named: effect.resourceName, voiceCount: voiceCount)
			}

			audioEngine.prepare()
			try! audioEngine.start()

			stateLock.lock()
			sounds = loadedSounds
			isPreloading = false
			stateLock.unlock()
		}
	}

	private func loadSound(named name: String, voiceCount: Int) -> VoiceCollection {
		guard let soundFileURL = Bundle.main.url(forResource: name, withExtension: "caf") else {
			fatalError("\(name).caf not found")
		}

		let audioFile = try! AVAudioFile(forReading: soundFileURL)
		guard let buffer = AVAudioPCMBuffer(
			pcmFormat: audioFile.processingFormat,
			frameCapacity: AVAudioFrameCount(audioFile.length)
		) else {
			fatalError("Unable to allocate an audio buffer for \(name).caf")
		}
		try! audioFile.read(into: buffer)

		let voices = (0..<voiceCount).map { _ in
			let voice = AVAudioPlayerNode()
			audioEngine.attach(voice)
			audioEngine.connect(voice, to: audioEngine.mainMixerNode, format: audioFile.processingFormat)
			voice.prepare(withFrameCount: buffer.frameLength)
			return voice
		}
		return VoiceCollection(buffer: buffer, voices: voices)
	}

	public func play(_ effect: Effect) {
		stateLock.lock()
		guard var voiceCollection = sounds[effect] else {
			stateLock.unlock()
			return
		}

		let voice = voiceCollection.voices[voiceCollection.nextVoice]
		voiceCollection.nextVoice = (voiceCollection.nextVoice + 1) % voiceCollection.voices.count
		sounds[effect] = voiceCollection

		voice.scheduleBuffer(voiceCollection.buffer, at: nil, options: .interrupts)
		if !voice.isPlaying {
			voice.play()
		}
		stateLock.unlock()
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
