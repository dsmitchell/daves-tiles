//
//  PuzzleTilePresentation.swift
//  daves-tiles
//

import SwiftUI

enum PuzzleBoardDepth {
	static let baseTile = 0.0
	static let tileLabel = 6.0
	static let elevatedTile = 8.0
}

struct PuzzleTilePresentation: Equatable {
	let id: Int
	let sourceRect: CGRect
	let destinationRect: CGRect
	let opacity: Float
	let cornerRadius: Float
	let contentInset: Float
	let borderWidth: Float
	let borderColor: SIMD4<Float>
	let animationDuration: Double
	let requiresSynchronizedPlacement: Bool
	let rendersInBaseLayer: Bool
	let rendersInElevatedLayer: Bool
	let depth: Double

	func disablingDuplicateAnimation() -> Self {
		Self(
			id: id,
			sourceRect: sourceRect,
			destinationRect: destinationRect,
			opacity: opacity,
			cornerRadius: cornerRadius,
			contentInset: contentInset,
			borderWidth: borderWidth,
			borderColor: borderColor,
			// The shared presentation animator drives both the Metal placement and
			// its SwiftUI label, so the renderer must not interpolate it a second time.
			animationDuration: 0,
			requiresSynchronizedPlacement: requiresSynchronizedPlacement,
			rendersInBaseLayer: rendersInBaseLayer,
			rendersInElevatedLayer: rendersInElevatedLayer,
			depth: depth
		)
	}

	func interpolated(from: Self, progress: Double) -> Self {
		func interpolate(_ start: CGFloat, _ end: CGFloat) -> CGFloat {
			start + (end - start) * progress
		}
		return Self(
			id: id,
			sourceRect: sourceRect,
			destinationRect: CGRect(
				x: interpolate(from.destinationRect.minX, destinationRect.minX),
				y: interpolate(from.destinationRect.minY, destinationRect.minY),
				width: interpolate(from.destinationRect.width, destinationRect.width),
				height: interpolate(from.destinationRect.height, destinationRect.height)
			),
			opacity: from.opacity + (opacity - from.opacity) * Float(progress),
			cornerRadius: from.cornerRadius + (cornerRadius - from.cornerRadius) * Float(progress),
			contentInset: from.contentInset + (contentInset - from.contentInset) * Float(progress),
			borderWidth: from.borderWidth + (borderWidth - from.borderWidth) * Float(progress),
			borderColor: from.borderColor + (borderColor - from.borderColor) * Float(progress),
			animationDuration: animationDuration,
			requiresSynchronizedPlacement: requiresSynchronizedPlacement,
			rendersInBaseLayer: rendersInBaseLayer,
			rendersInElevatedLayer: rendersInElevatedLayer,
			depth: from.depth + (depth - from.depth) * progress
		)
	}

	func applyingLayer(from latest: Self) -> Self {
		Self(
			id: id,
			sourceRect: sourceRect,
			destinationRect: destinationRect,
			opacity: opacity,
			cornerRadius: cornerRadius,
			contentInset: contentInset,
			borderWidth: borderWidth,
			borderColor: borderColor,
			animationDuration: animationDuration,
			requiresSynchronizedPlacement: requiresSynchronizedPlacement,
			rendersInBaseLayer: latest.rendersInBaseLayer,
			rendersInElevatedLayer: latest.rendersInElevatedLayer,
			depth: latest.depth
		)
	}
}

struct PuzzleTilePresentationFrame {
	let layoutsByID: [Int: PuzzleTilePresentation]
	let baseLayouts: [PuzzleTilePresentation]
	let elevatedLayouts: [PuzzleTilePresentation]
	let renderedTileIDs: Set<Int>
	let elevatedDepth: Double

	init(layouts: [PuzzleTilePresentation], latestLayoutsByID: [Int: PuzzleTilePresentation]) {
		var layoutsByID = [Int: PuzzleTilePresentation](minimumCapacity: layouts.count)
		var baseLayouts = [PuzzleTilePresentation]()
		var elevatedLayouts = [PuzzleTilePresentation]()
		baseLayouts.reserveCapacity(layouts.count)
		elevatedLayouts.reserveCapacity(layouts.count)
		var elevatedDepth = 0.0

		for presentedLayout in layouts {
			let layout = latestLayoutsByID[presentedLayout.id].map { presentedLayout.applyingLayer(from: $0) } ?? presentedLayout
			layoutsByID[layout.id] = layout
			let surfaceLayout = layout.disablingDuplicateAnimation()
			if layout.rendersInBaseLayer {
				baseLayouts.append(surfaceLayout)
			}
			if layout.rendersInElevatedLayer {
				elevatedLayouts.append(surfaceLayout)
				elevatedDepth = max(elevatedDepth, layout.depth)
			}
		}

		self.layoutsByID = layoutsByID
		self.baseLayouts = baseLayouts
		self.elevatedLayouts = elevatedLayouts
		self.renderedTileIDs = Set(layoutsByID.keys)
		self.elevatedDepth = elevatedLayouts.isEmpty
			? PuzzleBoardDepth.baseTile
			: max(elevatedDepth, PuzzleBoardDepth.elevatedTile)
	}
}

@Observable @MainActor
final class PuzzleTilePresentationAnimator {
	private struct PlacementAnimation {
		let from: PuzzleTilePresentation
		let to: PuzzleTilePresentation
		let startTime: TimeInterval

		func value(at time: TimeInterval) -> PuzzleTilePresentation {
			guard to.animationDuration > 0 else { return to }
			let rawProgress = min(1, max(0, (time - startTime) / to.animationDuration))
			let progress = rawProgress * rawProgress * (3 - 2 * rawProgress)
			return to.interpolated(from: from, progress: progress)
		}
	}

	private var animations = [Int: PlacementAnimation]()
	private var order = [Int]()
	private var animationTask: Task<Void, Never>?
	private(set) var isAnimating = false

	func update(to layouts: [PuzzleTilePresentation], at time: TimeInterval) {
		let previousAnimations = animations
		order = layouts.map(\.id)
		animations = Dictionary(
			uniqueKeysWithValues: layouts.map { layout in
				let previous = previousAnimations[layout.id]
				if let previous, previous.to == layout {
					return (layout.id, previous)
				}
				let current = previous?.value(at: time) ?? layout
				let hasValidOrigin =
					current.destinationRect.width > 0
					&& current.destinationRect.height > 0
				let origin = hasValidOrigin ? current : layout
				return (layout.id, PlacementAnimation(from: origin, to: layout, startTime: time))
			})
		let duration =
			animations.values
			.filter { animation in
				animation.from.destinationRect != animation.to.destinationRect
			}
			.map(\.to.animationDuration)
			.max() ?? 0
		animationTask?.cancel()
		isAnimating = duration > 0
		guard duration > 0 else { return }
		animationTask = Task { [weak self] in
			try? await Task.sleep(for: .seconds(duration))
			guard !Task.isCancelled else { return }
			self?.isAnimating = false
		}
	}

	func layouts(at time: TimeInterval, fallback: [PuzzleTilePresentation]) -> [PuzzleTilePresentation] {
		guard !animations.isEmpty else { return fallback }
		return order.compactMap { animations[$0]?.value(at: time) }
	}

	func frame(
		at time: TimeInterval,
		fallback: [PuzzleTilePresentation],
		latestLayoutsByID: [Int: PuzzleTilePresentation]
	) -> PuzzleTilePresentationFrame {
		PuzzleTilePresentationFrame(
			layouts: layouts(at: time, fallback: fallback),
			latestLayoutsByID: latestLayoutsByID
		)
	}
}
