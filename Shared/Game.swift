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

	enum Mode {
		case classic
		case swap
	}

	@Published var moves: Int = 0
	@Published var tiles: [Tile]
	
	var movementGroup: TileMovementGroup?
	var lingeringTileIdentifiers = [Int]()
	var image: CGImage? = UIImage(named: "PuzzleImage")?.cgImage{
		didSet { scaledImage = nil }
	}
	private var scaledImage: (size: CGSize, image: CGImage)?
	var initialized = false
	let openTileId: Int?

	init(rows: Int, columns: Int, mode: Mode = .swap) {
		self.rows = rows
		self.columns = columns
		let totalTiles = rows * columns
		self.openTileId = mode == .classic ? totalTiles : nil
		self.tiles = (1...totalTiles).map { Tile(id: $0) }
	}

	func imageMatching(size: CGSize) -> CGImage? {
		if let scaledImage = scaledImage, scaledImage.size == size { return scaledImage.image }
		guard let image = image else { return nil }
		let uiImage = UIImage(cgImage: image) // TODO: Get this to work with NSImage on mac as well (use CoreResolve probably)
		guard let resizedImage = uiImage.resized(toFill: size), let cgImage = resizedImage.cgImage else { return nil }
		scaledImage = (size, cgImage)
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

	@discardableResult func randomMove(except indices: [Int]? = nil) -> (from: Int, to: Int) {
		guard let openTile = tiles.firstIndex(where: { $0.id == openTileId }) else {
			var pair: (Int, Int)
			repeat {
				pair = (Int.random(in: 0..<tiles.count), Int.random(in: 0..<tiles.count))
			} while pair.0 == pair.1
			tiles.swapAt(pair.0, pair.1)
			return pair
		}
		var tileToMove: Int
		repeat {
			tileToMove = Int.random(in: 0..<tiles.count)
		} while (indices != nil && indices!.contains(tileToMove)) || !validJump(nextMove: tileToMove, openTile: openTile)
		tiles.swapAt(openTile, tileToMove)
		return (tileToMove, openTile)
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
