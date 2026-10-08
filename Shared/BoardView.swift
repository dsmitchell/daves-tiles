//
//  BoardView.swift
//  daves-tiles
//
//  Created by The App Studio LLC on 7/1/21.
//  Copyright © 2021 The App Studio LLC.
//

import Foundation
import SwiftUI

struct BoardView: View {

	static let standardDuration: Double = 0.1

	@Environment(\.colorScheme) private var colorScheme
	@Environment(\.puzzleImage) private var puzzleImage
	@Environment(\.puzzleImageIsPlaying) private var puzzleImageIsPlaying

	let popDuration = standardDuration
	let slideDuration = standardDuration
	let surpriseDuration = standardDuration * 2

	enum CompleteMoveBehavior {
		case rollback
		case proceed(swappingIdentifier: Int)
	}

	@State var game: Game
	@State var movementGroup: TileMovementGroup?
	@State var lingeringTileIdentifiers = [Int]()
	@State private var tileAnimationOwners = [Int: UUID]()
	@State private var activeMovementID: UUID?
	@State private var randomMoveIsInProgress = false

	struct SwapInfo: Equatable {
		let indices: [Int]
		let enabled: Bool
		let isTransitioning: Bool

		var animationIdentity: SwapAnimationIdentity {
			SwapAnimationIdentity(indices: indices, enabled: enabled)
		}
	}

	struct SwapAnimationIdentity: Equatable {
		let indices: [Int]
		let enabled: Bool
	}
	let swaps: SwapInfo?
	let interfaceIsLandscape: Bool?
	let showsTileNumbers: Bool
	let randomMoveRequestID: UUID?

	init(
		game: Game,
		swaps: SwapInfo?,
		interfaceIsLandscape: Bool? = nil,
		showsTileNumbers: Bool = true,
		randomMoveRequestID: UUID? = nil
	) {
		_game = State(initialValue: game)
		self.swaps = swaps
		self.interfaceIsLandscape = interfaceIsLandscape
		self.showsTileNumbers = showsTileNumbers
		self.randomMoveRequestID = randomMoveRequestID
	}

	func beginTracking(_ movementGroup: TileMovementGroup) {
		let movementID = UUID()
		activeMovementID = movementID
		for identifier in movementGroup.tileIdentifiers {
			tileAnimationOwners[identifier] = movementID
		}
		lingeringTileIdentifiers.removeAll(where: movementGroup.tileIdentifiers.contains)
	}

	func registerLingeringTiles(_ identifiers: [Int], owner movementID: UUID) {
		for identifier in identifiers {
			tileAnimationOwners[identifier] = movementID
			if !lingeringTileIdentifiers.contains(identifier) {
				lingeringTileIdentifiers.append(identifier)
			}
		}
	}

	func completeMove(behavior: CompleteMoveBehavior) {
		guard let movementGroup = movementGroup else { return }

		let duration: Double
		let tilesToDeselect: [Int]
		switch behavior {
		case .proceed(let swappingIdentifier):
			if movementGroup.numberOfMidpointCrossings % 2 == 0 {
				SoundEffects.default.play(.slide)
			}
			duration = movementGroup.direction == .drag ? surpriseDuration : slideDuration * (1 - movementGroup.lastPercentChange)
			tilesToDeselect = [swappingIdentifier] + movementGroup.tileIdentifiers
			game.moves += 1
			if duration > 0 {
				if movementGroup.direction == .drag {
					game.applyRenderState(.thrown, to: tilesToDeselect)
				} else {
					game.applyRenderState(.released(percent: movementGroup.lastPercentChange), to: movementGroup.tileIdentifiers)
				}
			}
			guard var swapIndex = game.tiles.firstIndex(where: { $0.id == swappingIdentifier }) else { return }
			for index in movementGroup.indices(in: game) {
				game.tiles.swapAt(swapIndex, index)
				swapIndex = index
			}
		case .rollback: // Undo the current move, which means the percent change also needs to be reversed
			duration = slideDuration * movementGroup.lastPercentChange
			tilesToDeselect = movementGroup.tileIdentifiers
			if duration > 0 {
				game.applyRenderState(.released(percent: 1 - movementGroup.lastPercentChange), to: movementGroup.tileIdentifiers)
			}
		}
		let movementID = activeMovementID ?? UUID()
		registerLingeringTiles(tilesToDeselect, owner: movementID)
		self.movementGroup = nil
		activeMovementID = nil
		Task {
			await deselectLingeringTiles(tilesToDeselect, ownedBy: movementID, after: duration)
		}
	}

	func deselectLingeringTiles(_ identifiers: [Int], ownedBy movementID: UUID, after duration: Double) async {
		if duration > 0 {
			try? await Task.sleep(nanoseconds: UInt64(Double(GameView.oneSecond) * duration))
		}

		let tilesToDeselect = identifiers.filter { tileAnimationOwners[$0] == movementID }
		let deselectionCount = tilesToDeselect.filter { identifier in
			game.tiles.first(where: { $0.id == identifier })?.isSelected == true
		}.count
		game.applyRenderState(.transitioning(toSelected: false), to: tilesToDeselect)

		if deselectionCount > 0 {
			try? await Task.sleep(nanoseconds: UInt64(Double(GameView.oneSecond) * popDuration))
		}

		let tilesToClear = identifiers.filter { tileAnimationOwners[$0] == movementID }
		game.applyRenderState(.none, to: tilesToClear)
		for identifier in tilesToClear {
			tileAnimationOwners.removeValue(forKey: identifier)
		}
		lingeringTileIdentifiers.removeAll(where: tilesToClear.contains)

		guard movementGroup == nil, lingeringTileIdentifiers.isEmpty, game.isFinished else { return }
		game.state = .finished
	}

	func randomMove() async {
		guard !randomMoveIsInProgress else { return }
		randomMoveIsInProgress = true
		defer { randomMoveIsInProgress = false }

		// Solvability/state-machine invariant for Nightmare mode:
		// 1. Capture the active movement group's indices before clearing it. Passing
		//    them to `randomMove(except:)` keeps the jump away from every tile that
		//    was participating in the interrupted user gesture.
		// 2. Roll back and clear that movement group before mutating the board.
		// 3. Ignore all gesture callbacks until the parity-preserving jump settles.
		// Keep these operations in this order; otherwise an interrupted gesture can
		// apply a second swap using state from before the jump and make the puzzle
		// unsolvable.
		let indices = movementGroup?.indices(in: game)
		completeMove(behavior: .rollback)
		let movedTileIndices = game.randomMove(except: indices)
		let movedTileIds = movedTileIndices.map { index in
			game.tiles[index].id
		}
		for index in movedTileIndices {
			game.tiles[index].renderState = .thrown
		}
		SoundEffects.default.play(.jump)
		let interval = Double(GameView.oneSecond) * surpriseDuration
		try? await Task.sleep(nanoseconds: UInt64(interval))
		movedTileIds.compactMap({ id in game.tiles.firstIndex(where: { $0.id == id }) }).forEach { index in
			game.tiles[index].renderState = .none
		}
		guard game.isFinished else { return }
		game.state = .finished
	}

	func swapAnimation(_ tile: Tile) -> Animation? {
		guard let swaps = swaps else { return nil }
		guard let index = game.tiles.firstIndex(where: { $0.id == tile.id }), swaps.indices.contains(index) else { return nil }
		return .linear(duration: surpriseDuration * 2)
	}

	func tileMovementAnimation(_ tile: Tile) -> Animation? {
		guard swaps == nil else { return nil }
		switch tile.renderState {
		case .none: return game.state == .new ? .spring(dampingFraction: 0.75, blendDuration: 1.0) : nil
		case .released(let percent) where percent < 1.0: return .linear(duration: tileImageAnimationDuration(tile))
		case .thrown: return .linear(duration: tileImageAnimationDuration(tile))
		case .transitioning: return .linear(duration: tileImageAnimationDuration(tile))
		default: return nil
		}
	}

	func tileImageAnimationDuration(_ tile: Tile) -> Double {
		if let swaps,
			let index = game.tiles.firstIndex(where: { $0.id == tile.id }),
			swaps.indices.contains(index) {
			return surpriseDuration * 2
		}
		switch tile.renderState {
		case .none:
			return game.state == .new ? 0.5 : 0
		case .released(let percent) where percent < 1:
			return slideDuration * (1 - percent)
		case .thrown:
			return surpriseDuration
		case .transitioning:
			return popDuration
		default:
			return 0
		}
	}

	func requiresSynchronizedPlacement(_ tile: Tile) -> Bool {
		if tile.renderState == .thrown {
			return true
		}
		guard let swaps,
			let index = game.tiles.firstIndex(where: { $0.id == tile.id }) else {
			return false
		}
		return swaps.indices.contains(index)
	}

	func tileFallingAnimation(_ tile: Tile) -> Animation? {
		guard tile.isFalling else { return nil }
#if os(visionOS)
		return .easeOut(duration: 0.5)
#else
		return .easeIn(duration: 1)
#endif
	}

	func tileOffset(_ tile: Tile) -> CGSize {
		guard swaps == nil, tile.renderState == .dragged, let movementGroup = movementGroup else { return .zero }
		return CGSize(width: movementGroup.positionOffset.dx, height: movementGroup.positionOffset.dy)
	}

	func tileOffsetZ(_ tile: Tile) -> Double {
		guard let swaps = swaps else {
			guard tile.renderState == .unset else {
				return tile.isSelected ? 8 : 0
			}
			return 640
		}
		if swaps.enabled, let index = game.tiles.firstIndex(where: { $0.id == tile.id }), swaps.indices.contains(index) {
			return 8
		}
		return tile.isSelected ? 8 : 0
	}

	func tileOpacity(_ tile: Tile, isOpen: Bool) -> Double {
		guard swaps == nil else { return isOpen ? 0 : 1 }
#if os(visionOS)
		if case .unset = tile.renderState, game.state == .new {
			return 0
		}
#endif
		guard isOpen && game.state != .finished else { return 1 }
		return 0
	}

	func tilePosition(_ tile: Tile, with position: CGPoint, in geometry: GeometryProxy) -> CGPoint {
		guard swaps == nil, tile.renderState == .unset else { return position }
#if os(visionOS)
		return CGPoint(x: tile.id % 2 == 0 ? 0 : geometry.size.width, y: geometry.size.height / 2)
#else
		return CGPoint(x: geometry.size.width / 2, y: geometry.size.height * 1.25)
#endif
	}

	func trackingPosition(for tile: Tile) -> Int? {
		return lingeringTileIdentifiers.firstIndex(of: tile.id) ?? movementGroup?.tileIdentifiers.firstIndex(of: tile.id)
	}

	func useTileGesture(_ tile: Tile) -> Bool {
		guard swaps == nil, game.state == .playing, !randomMoveIsInProgress else { return false }
#if os(visionOS) // Temporary workaround for gestures continuing on visionOS
		guard lingeringTileIdentifiers.isEmpty else { return false }
#endif
		guard movementGroup == nil || movementGroup!.isTracking(tile, in: game) || movementGroup!.direction == .drag else { return false }
		return true
	}

	func puzzleImageLayouts(
		for tiles: [Tile],
		boardGeometry: BoardGeometry,
		geometry: GeometryProxy
	) -> [PuzzleTilePresentation] {
		let borderColor: SIMD4<Float> = colorScheme == .dark
			? SIMD4(1, 1, 1, 1)
			: SIMD4(0, 0, 0, 1)
		return tiles.map { tile in
			let index = index(for: tile)
			let sourceFrame = boardGeometry.frame(for: tile.id)
			let position = tilePosition(tile, with: boardGeometry.positions[index], in: geometry)
			let offset = tileOffset(tile)
#if os(visionOS)
			let scale = 1.0
#else
			let scale = tile.isSelected ? 1.15 : 1.0
#endif
			let size = CGSize(
				width: boardGeometry.tileSize.width * scale,
				height: boardGeometry.tileSize.height * scale
			)
			return PuzzleTilePresentation(
				id: tile.id,
				sourceRect: CGRect(
					x: sourceFrame.minX / boardGeometry.boardSize.width,
					y: sourceFrame.minY / boardGeometry.boardSize.height,
					width: sourceFrame.width / boardGeometry.boardSize.width,
					height: sourceFrame.height / boardGeometry.boardSize.height
				),
				destinationRect: CGRect(
					x: position.x + offset.width - size.width / 2,
					y: position.y + offset.height - size.height / 2,
					width: size.width,
					height: size.height
				),
				opacity: Float(tileOpacity(tile, isOpen: tile.id == game.openTileId)),
				cornerRadius: Float(tile.isSelected || !game.isMatched(tile: tile, index: index) ? 8 : 0),
				contentInset: tile.isSelected || !game.isMatched(tile: tile, index: index) ? 1 : 0,
				// SwiftUI's four-point stroke is centered on the tile edge, and
				// clipping leaves its inner half visible. Metal draws inward.
				borderWidth: tile.isSelected ? 2 : 0,
				borderColor: borderColor,
				animationDuration: tileImageAnimationDuration(tile),
				requiresSynchronizedPlacement: requiresSynchronizedPlacement(tile)
			)
		}
	}

	func tileNumberIsCovered(
		_ tile: Tile,
		boardGeometry: BoardGeometry,
		geometry: GeometryProxy
	) -> Bool {
		guard let movementGroup,
			movementGroup.direction == .drag,
			!movementGroup.tileIdentifiers.contains(tile.id) else { return false }
		let labelPosition = boardGeometry.positions[index(for: tile)]
		return movementGroup.tileIdentifiers.contains { movingTileID in
			guard let movingTile = game.tiles.first(where: { $0.id == movingTileID }) else { return false }
			let movingIndex = index(for: movingTile)
			let position = tilePosition(
				movingTile,
				with: boardGeometry.positions[movingIndex],
				in: geometry
			)
			let offset = tileOffset(movingTile)
#if os(visionOS)
			let scale = 1.0
#else
			let scale = movingTile.isSelected ? 1.15 : 1.0
#endif
			let size = CGSize(
				width: boardGeometry.tileSize.width * scale,
				height: boardGeometry.tileSize.height * scale
			)
			let movingFrame = CGRect(
				x: position.x + offset.width - size.width / 2,
				y: position.y + offset.height - size.height / 2,
				width: size.width,
				height: size.height
			)
			return movingFrame.contains(labelPosition)
		}
	}

	var body: some View {
		GeometryReader { geometry in
#if os(iOS)
			let resolvedIsLandscape = interfaceIsLandscape
#else
			let resolvedIsLandscape = puzzleImage?.isLandscape
#endif
			let boardGeometry = BoardGeometry(game: game, geometryProxy: geometry, interfaceIsLandscape: resolvedIsLandscape)
			let dragGesture = DragGesture(minimumDistance: 0).onChanged { value in
				guard !randomMoveIsInProgress else { return }
				switch movementGroup {
				case .none where game.mode == .classic || value.velocity == .zero:
					guard let movementGroup = game.startDrag(value, with: boardGeometry) else { return }
					beginTracking(movementGroup)
					self.movementGroup = movementGroup
					if movementGroup.direction == .drag {
						SoundEffects.default.play(.popUp)
					}
				case .some(let movementGroup) where movementGroup.direction != .none && movementGroup.trackingState != nil:
					game.applyRenderState(.dragged, to: movementGroup.tileIdentifiers)
					if self.movementGroup!.applyDragGestureCrossedMidpoint(value) {
						SoundEffects.default.play(.slide)
					}
				case .some(let movementGroup) where movementGroup.trackingState == nil:
					guard let tappedTileIndex = boardGeometry.tileIndex(from: value.location) else { return }
					if movementGroup.indices(in: game).contains(tappedTileIndex) {
						self.movementGroup?.trackingState = .restarted
					} else {
						completeMove(behavior: .proceed(swappingIdentifier: game.tiles[tappedTileIndex].id))
					}
				default:
					break
				}
			}
			.onEnded { value in
				guard !randomMoveIsInProgress else { return }
				// Check whether we need to handle Swap mode before completing the touch
				if let movementGroup = movementGroup, movementGroup.direction == .drag, let droppedTileIndex = boardGeometry.tileIndex(from: value.location) {
					if movementGroup.indices(in: game).contains(droppedTileIndex) {
						switch (movementGroup.trackingState, movementGroup.possibleTap) {
						case (.restarted, true):
							SoundEffects.default.play(.popDown)
							fallthrough
						case (.restarted, false):
							let movementID = activeMovementID ?? UUID()
							registerLingeringTiles(movementGroup.tileIdentifiers, owner: movementID)
							self.movementGroup = nil
							activeMovementID = nil
							Task {
								await deselectLingeringTiles(movementGroup.tileIdentifiers, ownedBy: movementID, after: 0)
							}
						case (_, false):
							completeMove(behavior: .rollback)
						default:
							self.movementGroup?.trackingState = nil
						}
					} else { // We're dropping onto another tile
						completeMove(behavior: .proceed(swappingIdentifier: game.tiles[droppedTileIndex].id))
					}
				} else if let movementGroup = movementGroup, movementGroup.willMoveNext, let openTileId = game.openTileId {
					completeMove(behavior: .proceed(swappingIdentifier: openTileId))
				} else {
					completeMove(behavior: .rollback)
				}
			}
			ZStack {
				let sortedTiles = game.tiles.sorted { leftTile, rightTile in
					// First check if this is a SwapInfo tile
					if let swaps = swaps, let leftIndex = game.tiles.firstIndex(where: { $0.id == leftTile.id }), let rightIndex = game.tiles.firstIndex(where: { $0.id == rightTile.id }) {
						switch (swaps.indices.firstIndex(of: leftIndex), swaps.indices.firstIndex(of: rightIndex)) {
						case (.none, .some): return true
						case (.some(let leftPosition), .some(let rightPosition)): return leftPosition < rightPosition
						case (.some, _): return false
						default: return leftIndex < rightIndex
						}
					}
					// A random throw is _always_ at the end of the sorted list (i.e. on top)
					switch (leftTile.renderState, rightTile.renderState) {
					case (.thrown, .thrown): break // let trackingPosition decide
					case (.thrown, _): return false
					case (_, .thrown): return true
					default: break // let trackingPosition decide
					}
					// Otherwise any tile with a tracking position is sorted towards the end
					switch (trackingPosition(for: leftTile), trackingPosition(for: rightTile)) {
					case (.none, .some): return true
					case (.some(let leftPosition), .some(let rightPosition)): return leftPosition < rightPosition
					default: return false
					}
				}
				let compositedStillTileIDs = Set(sortedTiles.compactMap { tile in
					let index = index(for: tile)
					let tileIndex = game.tiles.firstIndex(where: { $0.id == tile.id })
					let imageIsTransitioning: Bool
					if let swaps, let tileIndex {
						imageIsTransitioning = swaps.isTransitioning && swaps.indices.contains(tileIndex)
					} else {
						imageIsTransitioning = false
					}
					let imageIsSettled = !imageIsTransitioning && (swaps != nil || tile.renderState == .none || tile.renderState == .falling)
					let imageIsVisible = tileOpacity(tile, isOpen: tile.id == game.openTileId) > 0
					return imageIsSettled && imageIsVisible && game.isMatched(tile: tile, index: index)
						? tile.id
						: nil
				})
				PuzzleImageBoardComposition(
					puzzleImage: puzzleImage,
					isPlaying: puzzleImageIsPlaying,
					contentSize: boardGeometry.boardSize,
					layouts: puzzleImageLayouts(for: sortedTiles, boardGeometry: boardGeometry, geometry: geometry),
					compositedStillTileIDs: compositedStillTileIDs
				) { surfaceRenderedTileIDs, presentationLayouts in
					ForEach(sortedTiles) { tile in
						let index = index(for: tile)
						let synchronizesPlacement = requiresSynchronizedPlacement(tile)
						let presentationPosition = synchronizesPlacement
							? presentationLayouts[tile.id].map { layout in
								CGPoint(x: layout.destinationRect.midX, y: layout.destinationRect.midY)
							} ?? boardGeometry.positions[index]
							: tilePosition(tile, with: boardGeometry.positions[index], in: geometry)
						let presentationOffset = synchronizesPlacement ? CGSize.zero : tileOffset(tile)
						let isMatched = game.isMatched(tile: tile, index: index)
						let isOpen = tile.id == game.openTileId
						let frame = boardGeometry.frame(for: tile.id)
						let imageRenderedByBoard = surfaceRenderedTileIDs.contains(tile.id)
						let showNumber = showsTileNumbers && ![.finished, .fading].contains(game.state)
							&& (!imageRenderedByBoard || !tileNumberIsCovered(tile, boardGeometry: boardGeometry, geometry: geometry))
						TileView(id: tile.id, isSelected: tile.isSelected, isMatched: isMatched, tileSize: boardGeometry.tileSize, drawsBorder: !imageRenderedByBoard, showNumber: showNumber, text: boardGeometry.text(for: tile.id), labelUsesSpatialDepth: game.state != .new) {
							PuzzleTileImage(id: tile.id, puzzleImage: puzzleImage, usesSharedSurface: imageRenderedByBoard, containerSize: boardGeometry.boardSize, tileRect: frame)
						}
						.id("tile.\(tile.id)")
						.frame(width: boardGeometry.tileSize.width, height: boardGeometry.tileSize.height)
						.position(presentationPosition)
						.offset(presentationOffset)
#if os(visionOS)
						.offset(z: tileOffsetZ(tile))
						.hoverEffect(isEnabled: useTileGesture(tile))
#endif
						.opacity(tileOpacity(tile, isOpen: isOpen))
						.animation(swapAnimation(tile), value: swaps?.animationIdentity)
						.animation(tileMovementAnimation(tile), value: tile.renderState)
						.gesture(!isOpen && useTileGesture(tile) ? dragGesture : nil)
					}
					if swaps == nil, game.state == .finished {
						ForEach(game.tiles) { tile in
							TileLabel(text: boardGeometry.text(for: tile.id), id: tile.id, tileSize: boardGeometry.tileSize)
								.position(boardGeometry.positions[tile.id-1])
#if os(visionOS)
								.offset(z: tile.isFalling ? 384 : 0)
#else
								.offset(x: 0, y: tile.isFalling ? boardGeometry.boardSize.height * 3 : 0)
#endif
								.opacity(tile.isFalling ? 0 : 1) // Fade out while falling
								.transition(showsTileNumbers ? .identity : .opacity.animation(.easeIn(duration: 1.0 / 3.0)))
								.animation(tileFallingAnimation(tile), value: tile.renderState)
						}
					}
				}
			}
		}
		.task(id: randomMoveRequestID) {
			guard randomMoveRequestID != nil else { return }
			await randomMove()
		}
	}

	func index(for tile: Tile) -> Int {
		guard let index = game.tiles.firstIndex(of: tile) else { fatalError("Tile with no index: \(tile.id)") }
		guard let swaps = swaps, swaps.enabled, let position = swaps.indices.firstIndex(of: index) else { return index }
		return swaps.indices[(position + 1) % swaps.indices.count]
	}
}

fileprivate extension Game {

	func startDrag(_ dragGesture: DragGesture.Value, with boardGeometry: BoardGeometry) -> TileMovementGroup? {
		guard let touchedTileIndex = boardGeometry.tileIndex(from: dragGesture.startLocation) else { return nil }
		guard tiles[touchedTileIndex].id != openTileId else { return nil } // Sometimes the boardGeometry returns the Open Tile
		var movementGroup = TileMovementGroup(startingWith: touchedTileIndex, in: self)
		guard ![.none].contains(movementGroup.direction) else { return movementGroup }
		movementGroup.applyMovementFunction(for: dragGesture, with: boardGeometry)
		applyRenderState(.transitioning(toSelected: true), to: movementGroup.tileIdentifiers)
		return movementGroup
	}
}

fileprivate extension Tile {

	var isFalling: Bool {
		switch renderState {
		case .unset, .falling: return true // Unset ensures detatched numbers are not prematurely drawn on the playing field
		default: return false
		}
	}
}

#Preview {
	return BoardView(game: Game(rows: 5, columns: 3, mode: .swap, imageIsLandscape: false), swaps: nil)
}
