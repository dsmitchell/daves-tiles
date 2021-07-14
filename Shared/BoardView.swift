//
//  BoardView.swift
//  davestiles
//
//  Created by The App Studio LLC on 7/1/21.
//

import SwiftUI

struct BoardView: View {

	@State var boardRendering: BoardRendering
	@State var timeToAnimate: CGFloat = 0.0
	@State var gameState: GameState = .new {
		didSet { print("GameState: \(gameState)") }
	}

	enum GameState {
		case new
		case starting
		case playing
		case finishing
		case finished
	}

	init(game: Game) {
		boardRendering = BoardRendering(game: game)
	}

	func randomMove() {
		boardRendering.randomMove()
	}

	func newGame() {
//		guard gameState != .starting else { return }
		if gameState != .new {
			gameState = .new
			boardRendering.startNewGame()
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
			gameState = .starting
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
			gameState = .playing
		}
	}

	func tileAnimation(_ tile: Tile) -> Animation? {
		// TODO: We want a more complex animation state (so that pop ups can animate)
		switch gameState {
		case .new:
			 return nil
		case .starting:
			return .spring(dampingFraction: 0.5, blendDuration: 1.0)
		default:
			return tile.isActive ? nil : .linear(duration: 0.1)
		}
	}

	func useTileGesture(_ tile: Tile) -> Bool {
		guard gameState == .playing else { return false }
		return !boardRendering.game.isFinished && (!boardRendering.tracking || tile.isTracking)
	}

	func tilePosition(_ tile: Tile, with position: CGPoint, in geometry: GeometryProxy) -> CGPoint {
		guard gameState != .new else {
			return CGPoint(x: geometry.size.width / 2, y: geometry.size.height * 1.25)
		}
		return tile.isActive ? position + boardRendering.positionOffset : position
	}

	var body: some View {
		ZStack {
			GeometryReader { geometry in
				let boardGeometry = boardRendering.boardGeometry(from: geometry)
				let dragGesture = DragGesture(minimumDistance: 0).onChanged { value in
					if boardRendering.tracking {
						boardRendering.continueTracking(dragGesture: value)
					} else {
						guard let touchedTileIndex = boardRendering.tileIndex(from: value.startLocation, with: boardGeometry) else { return }
						let movementGroup = boardRendering.game.tileMovementGroup(startingWith: touchedTileIndex)
						guard movementGroup.direction != .drag else { return }
						boardRendering.startTracking(movementGroup: movementGroup, from: value, with: boardGeometry)
					}
				}
				.onEnded { value in
					withAnimation(.linear(duration: 0.1 * (1 - boardRendering.lastPercentChange))) {
						timeToAnimate += 1
					}
					boardRendering.stopTracking()
				}
				ZStack {
					ForEach(boardRendering.arrangedTiles(with: boardGeometry), id: \.tile.id) { tile, image, position, isMatched in
						TileView(tile: tile, image: image, isMatched: isMatched)
							.opacity(tile.isOpen && !boardRendering.game.isFinished ? 0 : 1)
							.position(tilePosition(tile, with: position, in: geometry))
//							.animation(.linear(duration: 0.2 * (1 - boardRendering.lastPercentChange))) // This causes forever builds
							.animation(tileAnimation(tile))
							.frame(width: boardGeometry.tileSize.width, height: boardGeometry.tileSize.height)
							.gesture(useTileGesture(tile) ? dragGesture : nil)
					}
				}
				.onAnimationCompleted(for: timeToAnimate) {
					boardRendering.deselectTiles()
					if boardRendering.game.isFinished {
						gameState = .finishing
						SoundEffects.default.play(.gameWin)
					}
				}
			}
		}
		.onAppear {
			newGame()
		}
		.toolbar {
			ToolbarItemGroup(placement: .navigationBarTrailing) {
				Button(action: randomMove) {
					Label("Random Move", systemImage: "sparkles")
				}
				.disabled([.new, .starting, .finished, .finishing].contains(gameState))
				Button(action: newGame) {
					Label("New Game", systemImage: "restart.circle")
				}
				.disabled([.new, .starting].contains(gameState))
			}
		}
    }
}

/// An animatable modifier that is used for observing animations for a given animatable value.
struct AnimationCompletionObserverModifier<Value>: AnimatableModifier where Value: VectorArithmetic {

	/// While animating, SwiftUI changes the old input value to the new target value using this property. This value is set to the old value until the animation completes.
	var animatableData: Value {
		didSet {
			notifyCompletionIfFinished()
		}
	}

	/// The target value for which we're observing. This value is directly set once the animation starts. During animation, `animatableData` will hold the oldValue and is only updated to the target value once the animation completes.
	private var targetValue: Value

	/// The completion callback which is called once the animation completes.
	private var completion: () -> Void

	init(observedValue: Value, completion: @escaping () -> Void) {
		self.completion = completion
		self.animatableData = observedValue
		targetValue = observedValue
	}

	/// Verifies whether the current animation is finished and calls the completion callback if true.
	private func notifyCompletionIfFinished() {
		guard animatableData == targetValue else { return }

		/// Dispatching is needed to take the next runloop for the completion callback.
		/// This prevents errors like "Modifying state during view update, this will cause undefined behavior."
		DispatchQueue.main.async {
			self.completion()
		}
	}

	func body(content: Content) -> some View {
		/// We're not really modifying the view so we can directly return the original input value.
		return content
	}
}

extension View {

	/// Calls the completion handler whenever an animation on the given value completes.
	/// - Parameters:
	///   - value: The value to observe for animations.
	///   - completion: The completion callback to call once the animation completes.
	/// - Returns: A modified `View` instance with the observer attached.
	func onAnimationCompleted<Value: VectorArithmetic>(for value: Value, completion: @escaping () -> Void) -> ModifiedContent<Self, AnimationCompletionObserverModifier<Value>> {
		return modifier(AnimationCompletionObserverModifier(observedValue: value, completion: completion))
	}
}

fileprivate extension CGPoint {

	static func + (left: CGPoint, right: CGVector) -> CGPoint {
		return CGPoint(x: left.x + right.dx, y: left.y + right.dy)
	}
}
/*
extension CGVector: VectorArithmetic {

	public mutating func scale(by rhs: Double) {
		dx *= rhs
		dy *= rhs
	}

	public var magnitudeSquared: Double {
		pow(dx, 2) + pow(dy, 2)
	}

	public static func - (lhs: CGVector, rhs: CGVector) -> CGVector {
		CGVector(dx: lhs.dx - rhs.dx, dy: lhs.dy - rhs.dy)
	}

	public static func + (lhs: CGVector, rhs: CGVector) -> CGVector {
		CGVector(dx: lhs.dx + rhs.dx, dy: lhs.dy + rhs.dy)
	}
}
*/
struct BoardView_Previews: PreviewProvider {

    static var previews: some View {
		BoardView(game: Game(rows: 5, columns: 3))
    }
}
