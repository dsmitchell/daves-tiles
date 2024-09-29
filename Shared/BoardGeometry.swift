//
//  BoardGeometry.swift
//  daves-tiles
//
//  Created by The App Studio LLC on 7/3/21.
//  Copyright © 2021 The App Studio LLC.
//

import SwiftUI

struct BoardGeometry {

	private let game: Game
	public let boardSize: CGSize
	public let isLandscape: Bool
	public let positions: [CGPoint]
	public let tileSize: CGSize
	
	private static var numberFormatter: NumberFormatter = {
		let formatter = NumberFormatter()
		formatter.locale = .current
		formatter.numberStyle = .none
		return formatter
	}()

	init(game: Game, geometryProxy: GeometryProxy) {

		// Calculate geometry
		let rotated = geometryProxy.size.width > geometryProxy.size.height
		let columns = rotated ? game.rows : game.columns
		let rows = rotated ? game.columns : game.rows
		let length = min(geometryProxy.size.width / CGFloat(columns), geometryProxy.size.height / CGFloat(rows))
		let boardSize = CGSize(width: length * CGFloat(columns), height: length * CGFloat(rows))
		let offset = CGVector(dx: (geometryProxy.size.width - boardSize.width) / 2,
							  dy: (geometryProxy.size.height - boardSize.height) / 2)
		// Assign properties
		self.game = game
		self.boardSize = boardSize
		self.isLandscape = rotated
		self.positions = (0..<game.tiles.count).map { tileIndex in
			let gridIndex = game.gridIndex(for: tileIndex)
			let column = rotated ? gridIndex.row : gridIndex.column
			let row = rotated ? game.columns - gridIndex.column - 1 : gridIndex.row
			return CGPoint(x: (CGFloat(column) + 0.5) * length, y: (CGFloat(row) + 0.5) * length) + offset
		}
		self.tileSize = CGSize(width: length, height: length)
	}

	func image(for tile: Tile) -> Image? {
		guard boardSize != .zero, let image = PuzzleImages.imageMatching(size: boardSize) else { return nil }
		let tilePosition = tile.id - 1
		let gridIndex = (row: tilePosition / game.columns, column: tilePosition % game.columns)
		let column = isLandscape ? gridIndex.row : gridIndex.column
		let row = isLandscape ? game.columns - gridIndex.column - 1 : gridIndex.row
		let origin = CGPoint(x: CGFloat(column) * tileSize.width, y: CGFloat(row) * tileSize.height)
		let frame = CGRect(origin: origin, size: tileSize)
		guard let cgImage = image.cropping(to: frame) else { return nil }
		return Image(decorative: cgImage, scale: 1)
	}

	func text(for tile: Tile) -> String? {
		guard let identifier = number(for: tile) else { return nil }
		return BoardGeometry.numberFormatter.string(from: identifier)
	}
	
	private func number(for tile: Tile) -> NSNumber? {
		guard tile.id != game.openTileId else { return nil }
		guard isLandscape else { return NSNumber(integerLiteral: tile.id) }
		let gridIndex = game.gridIndex(for: tile.id - 1)
		return NSNumber(integerLiteral: game.rows * (game.columns - gridIndex.column - 1) + gridIndex.row + 1)
	}

	func tileIndex(from point: CGPoint) -> Int? {
		return positions.firstIndex { position in
			let origin = CGPoint(x: position.x - tileSize.width / 2, y: position.y - tileSize.height / 2)
			return CGRect(origin: origin, size: tileSize).contains(point)
		}
	}
}

extension CGPoint {

	static func + (left: CGPoint, right: CGVector) -> CGPoint {
		return CGPoint(x: left.x + right.dx, y: left.y + right.dy)
	}
}
