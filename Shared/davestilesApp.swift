//
//  davestilesApp.swift
//  daves-tiles
//
//  Created by The App Studio LLC on 6/14/21.
//  Copyright © 2021 The App Studio LLC.
//

import SwiftUI

@main struct davestilesApp: App {
	
	@State private var path: [GameSelection] = [] // Nothing on the stack by default.

    var body: some Scene {
		WindowGroup {
			NavigationStack(path: $path) {
				ContentView()
					.background(.clear)
			}
	#if !os(macOS)
			.navigationViewStyle(.stack)
	#endif
			.onAppear {
				SoundEffects.default.preloadSounds()
			}
        }
#if os(visionOS)
		.windowStyle(.plain)
		.defaultSize(Size3D(width: 0.5, height: 0.5, depth: 0.25), in: .meters)
#endif
    }
}
