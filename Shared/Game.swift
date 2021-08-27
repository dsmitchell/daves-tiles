//
//  Game.swift
//  davestiles
//
//  Created by The App Studio LLC on 7/6/21.
//

import SwiftUI
import CoreGraphics

class Game: ObservableObject, Identifiable {

	let id = UUID()
	let rows: Int
	let columns: Int

	enum Mode: Equatable {
		case classic
		case swap
	}

	@Published var moves: Int = 0
	@Published var tiles: [Tile]
	
	var movementGroup: TileMovementGroup?
	var lingeringTileIdentifiers = [Int]()
	var image: CGImage? = UIImage(named: "PuzzleImage")?.cgImage {
		didSet { scaledImages.removeAll() }
	}
	private var scaledImages = [CGSize : CGImage]()
	var initialized = false
	let openTileId: Int?

	init(rows: Int, columns: Int, mode: Mode) {
		self.rows = rows
		self.columns = columns
		let totalTiles = rows * columns
		self.openTileId = mode == .classic ? totalTiles : nil
		self.tiles = (1...totalTiles).map { Tile(id: $0) }
	}

	func imageMatching(size: CGSize) -> CGImage? {
		// TODO: Round the size to points so that we don't produce so many variations
		let roundedSize = CGSize(width: size.width.rounded(), height: size.height.rounded())
		if let scaledImage = scaledImages[roundedSize] { return scaledImage }
		print("Resizing image to \(roundedSize) (from \(size))")
		guard let image = image else { return nil }
		let uiImage = UIImage(cgImage: image) // TODO: Get this to work with NSImage on mac as well (use CoreResolve probably)
		guard let resizedImage = uiImage.resized(toFill: roundedSize), let cgImage = resizedImage.cgImage else { return nil }
		scaledImages[roundedSize] = cgImage
		return cgImage
	}

	func gridIndex(for index: Int) -> (row: Int, column: Int) {
		return (index / columns, index % columns)
	}

	var isFinished: Bool {
		tiles.enumerated().allSatisfy { index, element in
			isMatched(tile: element, index: index)
		}
	}

	func applyRenderState(_ renderState: Tile.RenderState, to tileIdentifiers: [Int]) {
		for id in tileIdentifiers {
			guard let index = tiles.firstIndex(where: { $0.id == id }) else { continue }
			tiles[index].renderState = renderState
		}
	}

	func isMatched(tile: Tile, index: Int? = nil) -> Bool {
		if let index = index {
			return tile.id == index + 1
		}
		return tile.id - 1 == tiles.firstIndex { tile.id == $0.id }
	}

	func startNewGame() {
		if initialized {
			let totalTiles = rows * columns
			self.tiles = (1...totalTiles).map { Tile(id: $0) }
		}
		repeat {
			randomMove()
		} while tiles.enumerated().contains { index, tile in
			isMatched(tile: tile, index: index)
		}
		self.moves = 0
		self.initialized = true
	}

	func trackingPosition(for tile: Tile) -> Int? {
		return lingeringTileIdentifiers.firstIndex(of: tile.id) ?? movementGroup?.tileIdentifiers.firstIndex(of: tile.id)
	}

	private func validJump(nextMove: Int, openTile: Int) -> Bool {
		guard nextMove != openTile else { return false }
		let nextGridIndex = gridIndex(for: nextMove)
		let openGridIndex = gridIndex(for: openTile)
		let deltaSum = abs(openGridIndex.row - nextGridIndex.row) + abs(openGridIndex.column - nextGridIndex.column);
		return /*deltaSum > 2 &&*/ deltaSum % 2 == 1
	}

	@discardableResult func randomMove(except indices: [Int]? = nil) -> [Int] {
		guard let openTile = tiles.firstIndex(where: { $0.id == openTileId }) else {
			var moves = [Int]()
			repeat {
				var tileToMove: Int
				repeat {
					tileToMove = Int.random(in: 0..<tiles.count)
				} while (indices != nil && indices!.contains(tileToMove)) || moves.contains(tileToMove)
				moves.append(tileToMove)
				let lastTwo = moves.suffix(2)
				if lastTwo.count == 2, let left = lastTwo.first, let right = lastTwo.last {
					tiles.swapAt(left, right)
				}
			} while moves.count < min(columns, rows) // We expect columns to always be the smaller number
			return moves
		}
		var tileToMove: Int
		repeat {
			tileToMove = Int.random(in: 0..<tiles.count)
		} while (indices != nil && indices!.contains(tileToMove)) || !validJump(nextMove: tileToMove, openTile: openTile)
		tiles.swapAt(openTile, tileToMove)
		return [openTile]
	}
}

extension CGSize: Hashable {

	public func hash(into hasher: inout Hasher) {
		hasher.combine(self.width)
		hasher.combine(self.height)
	}
}

fileprivate extension CGSize {

	static func * (left: CGSize, right: CGFloat) -> CGSize {
		return CGSize(width: left.width + right, height: left.height + right)
	}
}

fileprivate extension UIImage {

	func resized(toFill outputSize: CGSize) -> UIImage? {
		let scale = self.scale * max(outputSize.width / size.width, outputSize.height / size.height)
		let width = size.width * scale
		let height = size.height * scale
		let imageRect = CGRect(x: (outputSize.width - width) / 2.0, y: (outputSize.height - height) / 2.0, width: width, height: height)
		UIGraphicsBeginImageContextWithOptions(outputSize, true, 1)
		defer {
			UIGraphicsEndImageContext()
		}
		draw(in: imageRect)
		return UIGraphicsGetImageFromCurrentImageContext()
	}
}
