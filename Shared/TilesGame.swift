//
//  TilesGame.swift
//  daves-tiles
//
//  Created by David Mitchell on 3/25/24.
//

protocol TilesGame {
	var rows: Int { get }
	var columns: Int { get }
	var tiles: [Tile] { get set }
	var openTileId: Int? { get }
}

extension TilesGame {

	func gridIndex(for index: Int) -> (row: Int, column: Int) {
		return (index / columns, index % columns)
	}

	private func validJump(nextMove: Int, openTile: Int) -> Bool {
		guard nextMove != openTile else { return false }
		let nextGridIndex = gridIndex(for: nextMove)
		let openGridIndex = gridIndex(for: openTile)
		let deltaSum = abs(openGridIndex.row - nextGridIndex.row) + abs(openGridIndex.column - nextGridIndex.column);
		return /*deltaSum > 2 &&*/ deltaSum % 2 == 1
	}

	@discardableResult mutating func randomMove(except indices: [Int]? = nil) -> [Int] {
		guard let openTileId = openTileId, let openTile = tiles.firstIndex(where: { $0.id == openTileId }) else {
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
