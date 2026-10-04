//
//  PuzzleImageBoard.swift
//  daves-tiles
//

import SwiftUI

struct PuzzleImageSurface: View {

	let puzzleImage: PuzzleImage?
	let isPlaying: Bool
	let contentSize: CGSize
	let layouts: [PuzzleTilePresentation]
	let compositedStillTileIDs: Set<Int>
	let livePhotoIsReady: Bool
	let didRenderFirstFrame: () -> Void

	static func rendersLivePhoto(_ puzzleImage: PuzzleImage?) -> Bool {
		puzzleImage?.livePhotoMovieURL != nil
	}

	@ViewBuilder var body: some View {
		if Self.rendersLivePhoto(puzzleImage), isPlaying, let puzzleImage, let movieURL = puzzleImage.livePhotoMovieURL {
			ZStack {
				if !compositedStillTileIDs.isEmpty {
					StillPuzzleImageSurface(
						puzzleImage: puzzleImage,
						contentSize: contentSize,
						layouts: layouts.filter { compositedStillTileIDs.contains($0.id) }
					)
					.opacity(livePhotoIsReady ? 0 : 1)
				}
				LivePhotoBoardRenderer(
					id: puzzleImage.id,
					movieURL: movieURL,
					isPlaying: isPlaying,
					contentSize: contentSize,
					placements: layouts,
					didRenderFirstFrame: didRenderFirstFrame
				)
				.opacity(livePhotoIsReady ? 1 : 0)
			}
			.allowsHitTesting(false)
		} else if let puzzleImage, !compositedStillTileIDs.isEmpty {
			StillPuzzleImageSurface(
				puzzleImage: puzzleImage,
				contentSize: contentSize,
				layouts: layouts.filter { compositedStillTileIDs.contains($0.id) }
			)
			.allowsHitTesting(false)
		}
	}
}

private struct StillPuzzleImageSurface: View {

	let puzzleImage: PuzzleImage
	let contentSize: CGSize
	let layouts: [PuzzleTilePresentation]

	var body: some View {
		if let anchor = layouts.first {
			let origin = CGPoint(
				x: anchor.destinationRect.minX - anchor.sourceRect.minX * contentSize.width,
				y: anchor.destinationRect.minY - anchor.sourceRect.minY * contentSize.height
			)
			GeometryReader { geometry in
				ZStack(alignment: .topLeading) {
					puzzleImage.image(toFill: contentSize)
						.resizable()
						.scaledToFill()
						.frame(width: contentSize.width, height: contentSize.height)
						.clipped()
						.position(
							x: origin.x + contentSize.width / 2,
							y: origin.y + contentSize.height / 2
						)
				}
				.frame(width: geometry.size.width, height: geometry.size.height)
				.mask {
					Canvas { context, _ in
						var path = Path()
						for layout in layouts {
							path.addRect(layout.destinationRect)
						}
						context.fill(
							path,
							with: .color(.white),
							style: FillStyle(eoFill: false, antialiased: false)
						)
					}
				}
			}
		}
	}
}

struct PuzzleImageBoardComposition<Content: View>: View {

	@State private var readyLivePhotoID: String?
	@State private var presentationAnimator = PuzzleTilePresentationAnimator()

	let puzzleImage: PuzzleImage?
	let isPlaying: Bool
	let contentSize: CGSize
	let layouts: [PuzzleTilePresentation]
	let compositedStillTileIDs: Set<Int>
	@ViewBuilder let content: (Set<Int>, [Int: PuzzleTilePresentation]) -> Content

	var body: some View {
		let usesLivePhotoSurface = PuzzleImageSurface.rendersLivePhoto(puzzleImage)
		let sharedSurfaceIsReady = readyLivePhotoID == puzzleImage?.id
		let surfaceRenderedTileIDs = usesLivePhotoSurface && isPlaying
			? (sharedSurfaceIsReady ? Set(layouts.map(\.id)) : compositedStillTileIDs)
			: compositedStillTileIDs
		TimelineView(.animation(paused: !presentationAnimator.isAnimating)) { context in
			let presentationLayouts = presentationAnimator.layouts(
				at: context.date.timeIntervalSinceReferenceDate,
				fallback: layouts
			)
			let presentationLayoutsByID = Dictionary(
				uniqueKeysWithValues: presentationLayouts.map { ($0.id, $0) }
			)
			ZStack {
				PuzzleImageSurface(
					puzzleImage: puzzleImage,
					isPlaying: isPlaying,
					contentSize: contentSize,
					layouts: presentationLayouts.map { $0.disablingDuplicateAnimation() },
					compositedStillTileIDs: compositedStillTileIDs,
					livePhotoIsReady: sharedSurfaceIsReady,
					didRenderFirstFrame: {
						readyLivePhotoID = puzzleImage?.id
					}
				)
				content(surfaceRenderedTileIDs, presentationLayoutsByID)
			}
		}
		.onAppear {
			presentationAnimator.update(
				to: layouts,
				at: Date.now.timeIntervalSinceReferenceDate
			)
		}
		.onChange(of: layouts) { _, layouts in
			presentationAnimator.update(
				to: layouts,
				at: Date.now.timeIntervalSinceReferenceDate
			)
		}
		.onChange(of: isPlaying) { _, isPlaying in
			if !isPlaying {
				readyLivePhotoID = nil
			}
		}
	}
}

struct PuzzleTileImage: View {

	let id: Int
	let puzzleImage: PuzzleImage?
	let usesSharedSurface: Bool
	let containerSize: CGSize
	let tileRect: CGRect

	@ViewBuilder var body: some View {
		if let puzzleImage {
			puzzleImage.image(toFill: containerSize)
				.resizable()
				.scaledToFill()
				.frame(width: containerSize.width.rounded(), height: containerSize.height.rounded())
				.clipped()
				.offset(x: -tileRect.minX, y: -tileRect.minY)
				.frame(width: tileRect.width, height: tileRect.height, alignment: .topLeading)
				.opacity(usesSharedSurface ? 0 : 1)
				.animation(nil, value: usesSharedSurface)
		} else {
			Color(hue: Double(id) / 24, saturation: 1, brightness: 1)
		}
	}
}
