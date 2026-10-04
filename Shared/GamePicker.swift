//
//  GamePicker.swift
//  daves-tiles
//
//  Created by David Mitchell on 3/23/24.
//

import Photos
import PhotosUI
import SwiftUI

struct GamePicker<Header: View>: View {

	@Environment(\.verticalSizeClass) private var verticalSizeClass
	@Environment(\.puzzleImage) private var puzzleImage
	@Binding var selectedGameId: Game.ID?
	@State private var carouselPosition: Game.ID?
	@State private var isAddingImage = false
	@State private var isPhotoPickerPresented = false
	@State private var isPresentingGame = false
	@State private var isShowingImageError = false
	@State private var isUserInteracting = false
	@State private var selectedPhoto: PhotosPickerItem?
	@State private var startRotation = Date.timeIntervalSinceReferenceDate

	let gameSelections: [GameSelection]
	let gameType: GameType
	private let onPuzzleImageAdded: (PuzzleImage) -> Void
	private let onSelectRandomPuzzleImage: () -> Void
	private let header: () -> Header

	init(
		selectedGameId: Binding<Game.ID?>,
		gameSelections: [GameSelection],
		gameType: GameType,
		onPuzzleImageAdded: @escaping (PuzzleImage) -> Void = { _ in },
		onSelectRandomPuzzleImage: @escaping () -> Void = {},
		@ViewBuilder header: @escaping () -> Header
	) {
		_selectedGameId = selectedGameId
		_carouselPosition = State(initialValue: selectedGameId.wrappedValue)
		self.gameSelections = gameSelections
		self.gameType = gameType
		self.onPuzzleImageAdded = onPuzzleImageAdded
		self.onSelectRandomPuzzleImage = onSelectRandomPuzzleImage
		self.header = header
	}

	var body: some View {
		carouselBody()
			.animation(.easeInOut(duration: 0.3), value: isPhotoPickerPresented)
			.overlay(alignment: .topLeading) {
				header()
					.padding([.top, .leading])
			}
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
						isPhotoPickerPresented = true
					} label: {
						Image(systemName: "photo.badge.plus")
					}
					.accessibilityLabel("Add Image")
					Button(action: onSelectRandomPuzzleImage) {
						Image(systemName: "shuffle")
					}
					.accessibilityLabel("Random Image")
				}
				.buttonStyle(.bordered)
				.disabled(isAddingImage)
				.padding()
			}
			.overlay(alignment: .bottomLeading) {
				if let selected = gameSelections.first(where: { $0.game.id == selectedGameId }) {
					Button(action: selectNextDifficulty) {
						Label(
							selected.difficulty.displayValue,
							systemImage: selected.difficulty.systemImage
						)
						.font(.headline)
					}
					.buttonStyle(.bordered)
					.disabled(isAddingImage)
					.accessibilityHint("Toggle difficulty")
					.padding()
				}
			}
#if !os(macOS)
			.toolbar(.hidden, for: .navigationBar)
#endif
			.photosPicker(
				isPresented: $isPhotoPickerPresented,
				selection: $selectedPhoto,
				matching: .images,
				preferredItemEncoding: .current,
				photoLibrary: .shared()
			)
			.onChange(of: selectedPhoto) { _, newPhoto in
				guard let newPhoto else { return }
				addPuzzleImage(from: newPhoto)
			}
			.alert("Couldn’t Add Image", isPresented: $isShowingImageError) {
				Button("OK", role: .cancel) {}
			} message: {
				Text("The selected photo couldn’t be loaded. Please try another image.")
			}
			.overlay {
				if isAddingImage {
					PuzzleImageLoadingOverlay()
						.transition(.opacity)
				}
			}
			.animation(.easeInOut(duration: 0.2), value: isAddingImage)
	}

	private func addPuzzleImage(from item: PhotosPickerItem) {
		isAddingImage = true
		Task {
			defer {
				isAddingImage = false
				selectedPhoto = nil
			}
			do {
				let imported = try await PuzzleImageImporter.importItem(item)
				defer { try? FileManager.default.removeItem(at: imported.url) }
					let puzzleImage = try await PuzzleImageLibrary.addUserMedia(imported)
				onPuzzleImageAdded(puzzleImage)
			} catch {
				isShowingImageError = true
			}
		}
	}

	private func selectNextDifficulty() {
		guard !isAddingImage, !gameSelections.isEmpty else { return }
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
			let shouldFlattenDepth = isPhotoPickerPresented
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
				.scrollDisabled(isAddingImage)
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
					if !isAddingImage, isUserInteracting, let newValue, newValue != selectedGameId {
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
		.allowsHitTesting(!isAddingImage && gameSelection.game.id == selectedGameId)
#if os(visionOS)
		.hoverEffectDisabled()
		.focusEffectDisabled()
#endif
		.simultaneousGesture(TapGesture().onEnded {
			guard !isAddingImage else { return }
			isPresentingGame = true
			selectedGameId = gameSelection.game.id
		})
	}

	@ViewBuilder func boardView(for game: Game) -> some View {
		TimelineView(.animation(paused: game.id != selectedGameId)) { context in
			let rotation = context.date.timeIntervalSinceReferenceDate - startRotation
			let showSwap = gameType.randomJumps && Int(floor(rotation)) % 4 < 2
			let swapTransitionDuration = BoardView.standardDuration * 4
			let isSwapTransitioning = rotation.truncatingRemainder(dividingBy: 2) < swapTransitionDuration
			let swaps = gameType.randomJumps
				? BoardView.SwapInfo(indices: swaps(for: game), enabled: showSwap, isTransitioning: isSwapTransitioning)
				: BoardView.SwapInfo(indices: [], enabled: false, isTransitioning: false)

			BoardView(game: game, swaps: swaps, interfaceIsLandscape: verticalSizeClass == .compact)
				.environment(\.puzzleImageIsPlaying, !isPresentingGame && game.id == selectedGameId)
				.rotation3DEffect(.degrees(isPhotoPickerPresented ? 0 : 2.6 * cos(rotation)), axis: (x: 1, y: 0, z: 0))
				.rotation3DEffect(.degrees(isPhotoPickerPresented ? 0 : 4.0 * sin(rotation)), axis: (x: 0, y: 1, z: 0))
				.rotation3DEffect(.degrees(isPhotoPickerPresented ? 0 : tan(rotation / 10.0)), axis: (x: 0, y: -1, z: 0))
#if os(visionOS)
				.offset(z: isPhotoPickerPresented ? 0 : 50 + 78 * (1 - cos(rotation / 5.0)))
#else
				.rotation3DEffect(.degrees(isPhotoPickerPresented ? 0 : 5), axis: (x: 1, y: 0, z: 0))
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

private struct PuzzleImageLoadingOverlay: View {

	var body: some View {
		ZStack {
			Color.black.opacity(0.35)
				.ignoresSafeArea()
				.contentShape(Rectangle())
			ProgressView("Preparing Puzzle Image…")
				.padding()
				.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
		}
		.accessibilityElement(children: .combine)
		.accessibilityAddTraits(.isModal)
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
