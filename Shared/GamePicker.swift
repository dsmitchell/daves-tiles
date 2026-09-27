//
//  GamePicker.swift
//  daves-tiles
//
//  Created by David Mitchell on 3/23/24.
//

import SwiftUI

struct GamePicker<Header: View>: View {

	@Environment(\.verticalSizeClass) private var verticalSizeClass
	@Binding var selectedGameId: Game.ID?
	@State private var carouselPosition: Game.ID?
	@State private var isUserInteracting = false

	let gameSelections: [GameSelection]
	let gameType: GameType
	let startRotation = Date.timeIntervalSinceReferenceDate
	private let header: () -> Header

	init(selectedGameId: Binding<Game.ID?>, gameSelections: [GameSelection], gameType: GameType, @ViewBuilder header: @escaping () -> Header) {
		_selectedGameId = selectedGameId
		_carouselPosition = State(initialValue: selectedGameId.wrappedValue)
		self.gameSelections = gameSelections
		self.gameType = gameType
		self.header = header
	}

	var body: some View {
		carouselBody()
			.overlay(alignment: .topLeading) {
				header()
					.padding([.top, .leading])
			}
			.overlay(alignment: .bottomTrailing) {
				if let selected = gameSelections.first(where: { $0.game.id == selectedGameId }) {
					Button(action: selectNextDifficulty) {
						Text(selected.difficulty.displayValue)
							.font(.headline)
							.foregroundStyle(Color.accentColor)
					}
					.buttonStyle(.plain)
					.accessibilityHint("Toggle difficulty")
						.padding()
				}
			}
			.toolbar(.hidden, for: .navigationBar)
	}

	private func selectNextDifficulty() {
		guard !gameSelections.isEmpty else { return }
		let currentIndex = gameSelections.firstIndex { $0.game.id == selectedGameId } ?? -1
		let nextSelection = gameSelections[(currentIndex + 1) % gameSelections.count]

		withAnimation(.easeInOut) {
			selectedGameId = nextSelection.game.id
			carouselPosition = nextSelection.game.id
		}
	}
		
	private func carouselBody() -> some View {
		GeometryReader { geometry in
#if os(iOS)
			let workspaceLength = (geometry.size.width + geometry.size.height) / 3
#else
			let workspaceLength = min(geometry.size.width * 0.5, 320)
#endif
			ScrollViewReader { proxy in
				ScrollView(.horizontal) {
					HStack(spacing: 24) {
						ForEach(gameSelections, id: \.game.id) { gameSelection in
							carouselCard(for: gameSelection, workspaceLength: workspaceLength)
								.frame(width: workspaceLength)
								.id(gameSelection.game.id)
								.scrollTransition(.interactive, axis: .horizontal) { content, phase in
									content
										.scaleEffect(phase.isIdentity ? 1 : 0.8)
										.opacity(phase.isIdentity ? 1 : 0.625)
	#if os(visionOS)
										.offset(z: 60 * (1 - abs(phase.value)))
	#endif
								}
						}
					}
					.frame(height: geometry.size.height)
					.scrollTargetLayout()
				}
				.contentMargins(.horizontal, max(0, (geometry.size.width - workspaceLength) / 2), for: .scrollContent)
				.scrollIndicators(.hidden)
				.defaultScrollAnchor(.center)
				.scrollPosition(id: $carouselPosition, anchor: .center)
				.scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
				.onAppear {
					carouselPosition = selectedGameId
				}
				.onChange(of: geometry.size.width) {
					guard !isUserInteracting, let selectedGameId else { return }
					proxy.scrollTo(selectedGameId, anchor: .center)
				}
				.onChange(of: gameSelections.map(\.game.id)) {
					carouselPosition = selectedGameId
				}
				.onChange(of: carouselPosition) { _, newValue in
					if isUserInteracting, let newValue {
						selectedGameId = newValue
					}
				}
				.onScrollPhaseChange { _, newPhase in
					if newPhase == .interacting {
						isUserInteracting = true
					} else if newPhase == .idle {
						isUserInteracting = false
					}
				}
			}
		}
	}

	@ViewBuilder
	private func carouselCard(for gameSelection: GameSelection, workspaceLength: CGFloat) -> some View {
		NavigationLink(value: gameSelection) {
			boardView(for: gameSelection.game)
				.frame(width: workspaceLength, height: workspaceLength)
			}
			.buttonStyle(.plain)
			.allowsHitTesting(gameSelection.game.id == selectedGameId)
	#if os(visionOS)
		.hoverEffectDisabled()
		.focusEffectDisabled()
#endif
		.simultaneousGesture(TapGesture().onEnded {
			selectedGameId = gameSelection.game.id
		})
	}

	@ViewBuilder func boardView(for game: Game) -> some View {
		TimelineView(.animation(paused: game.id != selectedGameId)) { context in
			let rotation = context.date.timeIntervalSinceReferenceDate - startRotation
			let showSwap = gameType.randomJumps && Int(floor(rotation)) % 4 < 2
			let swaps = gameType.randomJumps ? BoardView.SwapInfo(indices: swaps(for: game), enabled: showSwap) : BoardView.SwapInfo(indices: [], enabled: false)
			
			BoardView(game: game, swaps: swaps, interfaceIsLandscape: verticalSizeClass == .compact)
				.rotation3DEffect(.degrees(2.6 * cos(rotation)), axis: (x: 1, y: 0, z: 0))
				.rotation3DEffect(.degrees(4.0 * sin(rotation)), axis: (x: 0, y: 1, z: 0))
				.rotation3DEffect(.degrees(tan(rotation / 10.0)), axis: (x: 0, y: -1, z: 0))
#if os(visionOS)
				.offset(z: 50 + 78 * (1 - cos(rotation / 5.0)))
#else
				.rotation3DEffect(.degrees(15), axis: (x: 1.01333332, y: 1, z: 0.37))
#endif
		}
	}

	func swaps(for game: Game) -> [Int] {
		if let openTileId = game.openTileId, let openTileIndex = game.tiles.firstIndex(where: { $0.id == openTileId }) {
			return [openTileIndex, (openTileIndex + game.tiles.count / 3) % game.tiles.count]
		}
		let iterations = min(game.columns, game.rows)
		return (0..<iterations).map { iteration in
			(iteration * 2 + iteration * game.columns + game.tiles.count / iterations) % game.tiles.count
		}
	}
}

#Preview {
	@Previewable @State var selectedGameId: Game.ID?
	let gameSelections: [GameSelection] = []
	let gameType: GameType = .initial

	return GamePicker(selectedGameId: $selectedGameId, gameSelections: gameSelections, gameType: gameType) {
		Text("Dave's Tiles")
			.font(.title3.bold())
	}
}
