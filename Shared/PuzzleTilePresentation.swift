//
//  PuzzleTilePresentation.swift
//  daves-tiles
//

import SwiftUI

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
            animationDuration: requiresSynchronizedPlacement ? 0 : animationDuration,
            requiresSynchronizedPlacement: requiresSynchronizedPlacement
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
            requiresSynchronizedPlacement: requiresSynchronizedPlacement
        )
    }
}

@Observable @MainActor
final class PuzzleTilePresentationAnimator {
    private struct PlacementAnimation {
        let from: PuzzleTilePresentation
        let to: PuzzleTilePresentation
        let startTime: TimeInterval

        func value(at time: TimeInterval) -> PuzzleTilePresentation {
            guard to.requiresSynchronizedPlacement, to.animationDuration > 0 else { return to }
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
        animations = Dictionary(uniqueKeysWithValues: layouts.map { layout in
            let previous = previousAnimations[layout.id]
            if let previous, previous.to == layout {
                return (layout.id, previous)
            }
            let current = previous?.value(at: time) ?? layout
            return (layout.id, PlacementAnimation(from: current, to: layout, startTime: time))
        })
        let duration = layouts
            .filter(\.requiresSynchronizedPlacement)
            .map(\.animationDuration)
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
}
