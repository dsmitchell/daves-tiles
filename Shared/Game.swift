//
//  Game.swift
//  davestiles
//
//  Created by The App Studio LLC on 7/6/21.
//

import SwiftUI
import CoreGraphics

class Game: ObservableObject {

	typealias TileMovementGroup = (indices: [Int], direction: MoveDirection)

	enum MoveDirection {
		case up
		case down
		case left
		case right
		case drag
	}

	let rows: Int
	let columns: Int

	@Published var moves: Int = 0
	@Published var tiles: [Tile]
	var image: CGImage? = UIImage(named: "PuzzleImage")?.cgImage{
		didSet { scaledImage = nil }
	}
	private var scaledImage: (size: CGSize, image: CGImage)?

	init(rows: Int, columns: Int) {
		self.rows = rows
		self.columns = columns
		let totalTiles = rows * columns
		self.tiles = (1..<totalTiles).map { Tile(id: $0, isOpen: false) } + [Tile(id: totalTiles, isOpen: true)] // This is Classic mode
		startNewGame()
	}

	func imageMatching(size: CGSize) -> CGImage? {
		if let scaledImage = scaledImage, scaledImage.size == size {
			return scaledImage.image
		}
		guard let image = image else {
			return nil
		}
		let uiImage = UIImage(cgImage: image)
		guard let resizedImage = uiImage.resized(toFill: size), let cgImage = resizedImage.cgImage else {
			return nil
		}
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

	func selectTiles(with indices: [Int]) {
		for index in indices {
			tiles[index].isSelected = true
		}
		if let last = indices.last {
			tiles[last].isTracking = true
		}
	}

	func isMatched(tile: Tile, index: Int? = nil) -> Bool {
		if let index = index {
			return tile.id == index + 1
		}
		return tile.id - 1 == tiles.firstIndex { tile.id == $0.id }
	}

	func startNewGame() {
		let totalTiles = rows * columns
		self.tiles = (1..<totalTiles).map { Tile(id: $0, isOpen: false) } + [Tile(id: totalTiles, isOpen: true)] // This is Classic mode
		repeat {
			randomMove()
		} while tiles.enumerated().contains { index, tile in
			isMatched(tile: tile, index: index)
		}
		self.moves = 0
	}

	private func validJump(nextMove: Int, openTile: Int) -> Bool {
		guard nextMove != openTile else { return false }
		let nextGridIndex = gridIndex(for: nextMove)
		let openGridIndex = gridIndex(for: openTile)
		let deltaSum = abs(openGridIndex.row - nextGridIndex.row) + abs(openGridIndex.column - nextGridIndex.column);
		return /*deltaSum > 2 &&*/ deltaSum % 2 == 1
	}

	@discardableResult func randomMove(except indices: [Int]? = nil) -> (from: Int, to: Int) {
		guard let openTile = tiles.firstIndex(where: { $0.isOpen }) else {
//			Array(0..<tiles.count) // TODO: Draw 2 unique numbers from 0..<tiles.count
			return (0, 0)
		}
		var tileToMove: Int
		repeat {
			tileToMove = Int.random(in: 0..<tiles.count)
		} while (indices != nil && indices!.contains(tileToMove)) || !validJump(nextMove: tileToMove, openTile: openTile)
		tiles.swapAt(openTile, tileToMove)
		return (tileToMove, openTile)
	}

	func tileMovementGroup(startingWith tileIndex: Int) -> TileMovementGroup {
		// TODO: This rule follows Classic Mode. When Swap Mode is supported just use the default
		guard let openTile = tiles.firstIndex(where: { $0.isOpen }), openTile != tileIndex, tileIndex < tiles.count else {
			return ([tileIndex], .drag)
		}
		switch (gridIndex(for: openTile), gridIndex(for: tileIndex)) {
		case (let space, let tile) where space.column == tile.column && space.row < tile.row:
			return (Array(stride(from: openTile + columns, through: tileIndex, by: columns)), .up)
		case (let space, let tile) where space.column == tile.column && space.row > tile.row:
			return (Array(stride(from: tileIndex, to: openTile, by: columns).reversed()), .down)
		case (let space, let tile) where space.row == tile.row && space.column < tile.column:
			return (Array(openTile+1...tileIndex), .left)
		case (let space, let tile) where space.row == tile.row && space.column > tile.column:
			return (Array((tileIndex..<openTile).reversed()), .right)
		default:
			return ([tileIndex], .drag)
		}
	}

	func cancelMove(with movementGroup: TileMovementGroup) {
		for index in movementGroup.indices {
			tiles[index].isMoving = false
			tiles[index].isTracking = false // We want this to happen later (or maybe now)
		}
	}

	func completeMove(with movementGroup: TileMovementGroup) {
		moves += 1
		for index in movementGroup.indices {
			tiles[index].isMoving = false
			tiles[index].isTracking = false // We want this to happen later (or maybe now)
		}
		guard var openTile = tiles.firstIndex(where: { $0.isOpen }) else { return }
		for index in movementGroup.indices {
			tiles.swapAt(openTile, index)
			openTile = index
		}
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
