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
	@Published var openTile: Int? // TODO: Make optional to support Swap Mode
	@Published var tiles: [Tile]
	var image: CGImage? = UIImage(named: "PuzzleImage")?.cgImage{
		didSet { scaledImage = nil }
	}
	private var scaledImage: (size: CGSize, image: CGImage)?

	init(rows: Int, columns: Int) {
		self.rows = rows
		self.columns = columns
		let openTile = rows * columns - 1 // This is Classic Mode
		self.openTile = openTile
		self.tiles = (1...openTile).map { Tile(id: $0, isOpen: false) }
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
		let openTile = openTile ?? tiles.count + 1
		let position = index >= openTile ? index + 1 : index
		return (position / columns, position % columns)
	}

	var isFinished: Bool {
		tiles.enumerated().allSatisfy { index, element in
			isMatched(tile: element, index: index)
		}
	}

	var openGridIndex: (row: Int, column: Int) {
		let openTile = openTile ?? tiles.count + 1
		return (openTile / columns, openTile % columns)
	}

	func activateTiles(with indices: [Int]) {
		for index in indices {
			tiles[index].isActive = true
			tiles[index].isSelected = true
		}
		if let last = indices.last {
			tiles[last].isTracking = true
		}
	}

	func isMatched(tile: Tile, index: Int) -> Bool {
		let openTile = openTile ?? tiles.count + 1
		let indexIncrement = index >= openTile ? 2 : 1
		return tile.id == index + indexIncrement
	}

	func startNewGame() {
		let openTile = rows * columns - 1 // This is Classic Mode
		self.openTile = openTile
		self.tiles = (1...openTile).map { Tile(id: $0, isOpen: false) }
		repeat {
			randomMove()
		} while tiles.enumerated().contains { index, tile in
			isMatched(tile: tile, index: index)
		}
		self.moves = 0
	}

	private func validJump(nextMove: Int) -> Bool {
		guard nextMove != openTile else { return false }
		let nextGridIndex = gridIndex(for: nextMove)
		let deltaSum = abs(openGridIndex.row - nextGridIndex.row) + abs(openGridIndex.column - nextGridIndex.column);
		return /*deltaSum > 2 &&*/ deltaSum % 2 == 1
	}

	@discardableResult func randomMove() -> (from: Int, to: Int) {
		if openTile == nil {
//			Array(0..<tiles.count) // TODO: Draw 2 unique numbers from 0..<tiles.count
			return (0, 0)
		}
		let openTile = openTile ?? Int.max
		var tileToMove: Int
		repeat {
			tileToMove = Int.random(in: 0..<tiles.count)
		} while !validJump(nextMove: tileToMove)
		let tile = tiles.remove(at: tileToMove)
		var result: Int
		if tileToMove < openTile {
			result = openTile-1
			tiles.insert(tile, at: result)
			self.openTile = tileToMove
		} else {
			result = openTile
			tiles.insert(tile, at: result)
			self.openTile = tileToMove+1
		}
		return (tileToMove, result)
	}

	func tileMovementGroup(startingWith tileIndex: Int) -> TileMovementGroup {
		// TODO: This rule follows Classic Mode. When Swap Mode is supported just use the default
		guard let openTile = openTile else {
			return ([tileIndex], .drag)
		}
		switch (openGridIndex, gridIndex(for: tileIndex)) {
		case (let space, let tile) where space.column == tile.column && space.row < tile.row:
			return (Array(stride(from: openTile + columns - 1, through: tileIndex, by: columns)), .up)
		case (let space, let tile) where space.column == tile.column && space.row > tile.row:
			return (Array(stride(from: tileIndex, to: openTile, by: columns).reversed()), .down)
		case (let space, let tile) where space.row == tile.row && space.column < tile.column:
			return (Array(openTile...tileIndex), .left)
		case (let space, let tile) where space.row == tile.row && space.column > tile.column:
			return (Array((tileIndex..<openTile).reversed()), .right)
		default:
			return ([tileIndex], .drag)
		}
	}

	func cancelMove(with movementGroup: TileMovementGroup) {
		for index in movementGroup.indices {
			tiles[index].isActive = false
			tiles[index].isTracking = false // We want this to happen later (or maybe now)
		}
	}

	func completeMove(with movementGroup: TileMovementGroup) {
		moves += 1
		for index in movementGroup.indices {
			tiles[index].isActive = false
			tiles[index].isTracking = false // We want this to happen later (or maybe now)
		}
		let tileIndex = movementGroup.indices.last!
		switch movementGroup.direction {
		case .up:
			for index in movementGroup.indices {
				let tile = tiles.remove(at: index)
				tiles.insert(tile, at: index-columns+1)
			}
			openTile = tileIndex+1
		case .down:
			for index in movementGroup.indices {
				let tile = tiles.remove(at: index)
				tiles.insert(tile, at: index+columns-1)
			}
			openTile = tileIndex
		case .left:
			openTile = tileIndex + 1
		case .right:
			openTile = tileIndex
		default:
			break
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
