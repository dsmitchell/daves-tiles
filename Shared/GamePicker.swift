//
//  GamePicker.swift
//  daves-tiles
//
//  Created by David Mitchell on 3/23/24.
//

import SwiftUI

struct GamePicker<Header: View>: View {
	
	private struct BoardIdentity: Hashable {
		let gameID: Game.ID
		let isLandscape: Bool
	}

	@Environment(\.verticalSizeClass) private var verticalSizeClass
	@Environment(\.puzzleImage) private var puzzleImage
	@Environment(\.scenePhase) private var scenePhase
	@Binding var selectedGameId: Game.ID?
	@Binding var showsTileNumbers: Bool
	@State private var carouselPosition: Game.ID?
	@State private var isImageManagerPresented = false
	@State private var isPresentingGame = false
	@State private var isUserInteracting = false
	@State private var startRotation = Date.timeIntervalSinceReferenceDate
	@State private var suspendedRotationDate: Date?

	let gameSelections: [GameSelection]
	let gameType: GameType
	private let onPuzzleImageAdded: (PuzzleImage) -> Void
	private let onSelectRandomPuzzleImage: () -> Void
	private let header: () -> Header

	init(
		selectedGameId: Binding<Game.ID?>,
		showsTileNumbers: Binding<Bool>,
		gameSelections: [GameSelection],
		gameType: GameType,
		onPuzzleImageAdded: @escaping (PuzzleImage) -> Void = { _ in },
		onSelectRandomPuzzleImage: @escaping () -> Void = {},
		@ViewBuilder header: @escaping () -> Header
	) {
		_selectedGameId = selectedGameId
		_showsTileNumbers = showsTileNumbers
		_carouselPosition = State(initialValue: selectedGameId.wrappedValue)
		self.gameSelections = gameSelections
		self.gameType = gameType
		self.onPuzzleImageAdded = onPuzzleImageAdded
		self.onSelectRandomPuzzleImage = onSelectRandomPuzzleImage
		self.header = header
	}

	var body: some View {
		carouselBody()
			.overlay(alignment: .topLeading) {
				header()
					.scenePadding([.top, .leading])
			}
#if os(visionOS)
			.ornament(attachmentAnchor: .scene(.bottom)) {
				HStack {
					tileNumbersButton
					if let selected = gameSelections.first(where: { $0.game.id == selectedGameId }) {
						Button(action: selectNextDifficulty) {
							Label(
								selected.difficulty.displayValue,
								systemImage: selected.difficulty.systemImage
							)
							.font(.headline)
						}
						.buttonStyle(.bordered)
						.accessibilityHint("Toggle difficulty")
					}
					Spacer()
					Button {
						isImageManagerPresented = true
					} label: {
						Image(systemName: "photo.stack")
					}
					.accessibilityLabel("Manage Images")
					Button(action: onSelectRandomPuzzleImage) {
						Image(systemName: "shuffle")
					}
					.accessibilityLabel("Random Image")
				}
				.frame(minWidth: 320)
				.scenePadding()
				.glassBackgroundEffect()
			}
#else
			.overlay(alignment: .bottomTrailing) {
				HStack {
#if DEBUG
					if let resourceURLs = puzzleImage?.livePhotoResourceURLs {
						ShareLink(items: resourceURLs) {
							Image(systemName: "square.and.arrow.up")
						}
						.accessibilityLabel("Export Live Photo Resources")
					}
#endif
					Button {
						isImageManagerPresented = true
					} label: {
						Image(systemName: "photo.stack")
					}
					.accessibilityLabel("Manage Images")
					Button(action: onSelectRandomPuzzleImage) {
						Image(systemName: "shuffle")
					}
					.accessibilityLabel("Random Image")
				}
				.buttonStyle(.bordered)
					.padding()
			}
			.overlay(alignment: .bottomLeading) {
				HStack {
					tileNumbersButton
					if let selected = gameSelections.first(where: { $0.game.id == selectedGameId }) {
						Button(action: selectNextDifficulty) {
							Label(
								selected.difficulty.displayValue,
								systemImage: selected.difficulty.systemImage
							)
							.font(.headline)
						}
						.accessibilityHint("Toggle difficulty")
					}
				}
				.buttonStyle(.bordered)
				.scenePadding()
			}
#endif
#if !os(macOS)
			.toolbar(.hidden, for: .navigationBar)
#endif
			.sheet(isPresented: $isImageManagerPresented, onDismiss: {
				startRotation = Date.timeIntervalSinceReferenceDate
			}) {
				NavigationStack {
					PuzzleImageManagerView(
						onPuzzleImageAdded: onPuzzleImageAdded,
						onPuzzleImageDeleted: { deletedImageID in
							guard puzzleImage?.id == deletedImageID else { return }
							onSelectRandomPuzzleImage()
						}
					)
				}
			}
			.onChange(of: scenePhase, scenePhaseChanged)
		}

		private func scenePhaseChanged(_: ScenePhase, _ newPhase: ScenePhase) {
			switch newPhase {
			case .inactive, .background:
				if suspendedRotationDate == nil {
					suspendedRotationDate = Date()
				}
			case .active:
				if let suspendedRotationDate {
					startRotation += Date().timeIntervalSince(suspendedRotationDate)
					self.suspendedRotationDate = nil
				}
			@unknown default:
				break
			}
		}

	private var tileNumbersButton: some View {
		Button {
			withAnimation(.easeInOut(duration: BoardView.standardDuration)) {
				showsTileNumbers.toggle()
			}
		} label: {
			Image(systemName: showsTileNumbers ? "number.square.fill" : "number.square")
		}
		.accessibilityLabel(showsTileNumbers ? "Hide Tile Numbers" : "Show Tile Numbers")
	}

	private func selectNextDifficulty() {
		guard !gameSelections.isEmpty else { return }
		let currentIndex = gameSelections.firstIndex { $0.game.id == selectedGameId } ?? -1
		let nextSelection = gameSelections[(currentIndex + 1) % gameSelections.count]

		startRotation = Date.timeIntervalSinceReferenceDate
		withAnimation(.easeInOut) {
			selectedGameId = nextSelection.game.id
			carouselPosition = nextSelection.game.id
		}
	}

	private func carouselBody() -> some View {
		GeometryReader { geometry in
			let shouldFlattenDepth = isImageManagerPresented
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
										.offset(z: shouldFlattenDepth ? 0 : 60 * (1 - abs(phase.value)))
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
					startRotation = Date.timeIntervalSinceReferenceDate
					isPresentingGame = false
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
					if isUserInteracting, let newValue, newValue != selectedGameId {
						startRotation = Date.timeIntervalSinceReferenceDate
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
			isPresentingGame = true
			selectedGameId = gameSelection.game.id
		})
	}

	@ViewBuilder func boardView(for game: Game) -> some View {
		TimelineView(.animation(paused: scenePhase != .active || isImageManagerPresented || game.id != selectedGameId)) { context in
			let rotation = context.date.timeIntervalSinceReferenceDate - startRotation
			let showSwap = gameType.randomJumps && Int(floor(rotation)) % 4 < 2
			let swapTransitionDuration = BoardView.standardDuration * 4
			let isSwapTransitioning = rotation.truncatingRemainder(dividingBy: 2) < swapTransitionDuration
			let swaps = gameType.randomJumps
				? BoardView.SwapInfo(indices: swaps(for: game), enabled: showSwap, isTransitioning: isSwapTransitioning)
				: BoardView.SwapInfo(indices: [], enabled: false, isTransitioning: false)

			let isLandscape = verticalSizeClass == .compact
			BoardView(game: game, swaps: swaps, interfaceIsLandscape: isLandscape, showsTileNumbers: showsTileNumbers)
				.id(BoardIdentity(gameID: game.id, isLandscape: isLandscape))
//				.animation(.linear, value: isLandscape)
				.environment(\.puzzleImageIsPlaying, scenePhase == .active && !isImageManagerPresented && !isPresentingGame && game.id == selectedGameId)
				.rotation3DEffect(.degrees(isImageManagerPresented ? 0 : 2.6 * cos(rotation)), axis: (x: 1, y: 0, z: 0))
				.rotation3DEffect(.degrees(isImageManagerPresented ? 0 : 4.0 * sin(rotation)), axis: (x: 0, y: 1, z: 0))
				.rotation3DEffect(.degrees(isImageManagerPresented ? 0 : tan(rotation / 10.0)), axis: (x: 0, y: -1, z: 0))
#if os(visionOS)
				.offset(z: isImageManagerPresented ? 0 : 50 + 78 * (1 - cos(rotation / 5.0)))
#else
				.rotation3DEffect(.degrees(isImageManagerPresented ? 0 : 5), axis: (x: 1, y: 0, z: 0))
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
	@Previewable @State var showsTileNumbers = true
	let gameSelections: [GameSelection] = []
	let gameType: GameType = .initial

	return GamePicker(selectedGameId: $selectedGameId, showsTileNumbers: $showsTileNumbers, gameSelections: gameSelections, gameType: gameType) {
		Text("Dave's Tiles")
			.font(.title3.bold())
	}
}
