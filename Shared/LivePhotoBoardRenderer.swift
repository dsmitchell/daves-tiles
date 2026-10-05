//
//  LivePhotoBoardRenderer.swift
//  daves-tiles
//

@preconcurrency import AVFoundation
import CoreVideo
import Metal
import MetalKit
import SwiftUI

#if canImport(UIKit)
import UIKit
private typealias PlatformMetalViewRepresentable = UIViewRepresentable
#elseif canImport(AppKit)
import AppKit
private typealias PlatformMetalViewRepresentable = NSViewRepresentable
#endif

struct LivePhotoBoardRenderer: PlatformMetalViewRepresentable {

	@Environment(\.scenePhase) private var scenePhase

	private enum ContentCropStrategy {
		case fullFrame
		case darkPixelEdges
	}

	// Some Live Photo video compositions contain baked-in black bars. Keep the
	// pixel-based detector available until all supported asset variants can rely
	// on clean-aperture metadata alone.
	private static let contentCropStrategy = ContentCropStrategy.darkPixelEdges

	let id: String
	let movieURL: URL
	let isPlaying: Bool
	let contentSize: CGSize
	let placements: [PuzzleTilePresentation]
	let didRenderFirstFrame: () -> Void

	func makeCoordinator() -> Coordinator {
		Coordinator()
	}

#if canImport(UIKit)
	func makeUIView(context: Context) -> MTKView {
		makeMetalView(coordinator: context.coordinator)
	}

	func updateUIView(_ view: MTKView, context: Context) {
		update(view, coordinator: context.coordinator)
	}

	static func dismantleUIView(_ view: MTKView, coordinator: Coordinator) {
		coordinator.stop()
	}
#elseif canImport(AppKit)
	func makeNSView(context: Context) -> MTKView {
		makeMetalView(coordinator: context.coordinator)
	}

	func updateNSView(_ view: MTKView, context: Context) {
		update(view, coordinator: context.coordinator)
	}

	static func dismantleNSView(_ view: MTKView, coordinator: Coordinator) {
		coordinator.stop()
	}
#endif

	private var shouldRender: Bool {
		isPlaying && scenePhase == .active
	}

	private func makeMetalView(coordinator: Coordinator) -> MTKView {
		let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
		view.colorPixelFormat = .bgra8Unorm
		view.clearColor = MTLClearColorMake(0, 0, 0, 0)
#if canImport(UIKit)
		view.isOpaque = false
		view.isUserInteractionEnabled = false
#endif
		view.enableSetNeedsDisplay = false
		view.isPaused = !shouldRender
		view.preferredFramesPerSecond = 60
		coordinator.attach(to: view)
		return view
	}

	private func update(_ view: MTKView, coordinator: Coordinator) {
		view.isPaused = !shouldRender
		coordinator.update(
			id: id,
			movieURL: movieURL,
			isPlaying: shouldRender,
			contentSize: contentSize,
			placements: placements,
			didRenderFirstFrame: didRenderFirstFrame
		)
	}

	@MainActor final class Coordinator: NSObject, MTKViewDelegate {

		private struct TileInstance {
			var destinationRect: SIMD4<Float>
			var sourceRect: SIMD4<Float>
			var borderColor: SIMD4<Float>
			var cornerRadius: Float
			var opacity: Float
			var contentInset: Float
			var borderWidth: Float
		}

		private struct FrameUniforms {
			var viewAndContentSize: SIMD4<Float>
			var textureAndDrawableSize: SIMD4<Float>
			var visibleTextureRect: SIMD4<Float>
		}

		private struct PlacementAnimation {
			let from: PuzzleTilePresentation
			let to: PuzzleTilePresentation
			let startTime: CFTimeInterval

			func value(at time: CFTimeInterval) -> PuzzleTilePresentation {
				guard to.animationDuration > 0 else { return to }
				let rawProgress = min(1, max(0, (time - startTime) / to.animationDuration))
				let progress = rawProgress * rawProgress * (3 - 2 * rawProgress)

				return to.interpolated(from: from, progress: progress)
			}
		}

		private final class PendingPlayerConfiguration: @unchecked Sendable {
			let id: String
			let item: AVPlayerItem
			let output: AVPlayerItemVideoOutput

			init(id: String, item: AVPlayerItem, output: AVPlayerItemVideoOutput) {
				self.id = id
				self.item = item
				self.output = output
			}
		}

		private weak var view: MTKView?
		private var commandQueue: MTLCommandQueue?
		private var pipelineState: MTLRenderPipelineState?
		private var samplerState: MTLSamplerState?
		private var textureCache: CVMetalTextureCache?
		private var instanceBuffers = [MTLBuffer]()
		private var instanceBufferIndex = 0
		private var player: AVPlayer?
		private var playerItem: AVPlayerItem?
		private var videoOutput: AVPlayerItemVideoOutput?
		private var endObserver: NSObjectProtocol?
		private var statusObservation: NSKeyValueObservation?
		private var currentID: String?
		private var isPlaying = false
		private var isPrerolled = false
		private var placementAnimations = [Int: PlacementAnimation]()
		private var placementOrder = [Int]()
		private var contentSize = CGSize.zero
		private var lastPixelBuffer: CVPixelBuffer?
		private var visibleTextureRect: CGRect?
		private var didRenderFirstFrame: (() -> Void)?
		private var reportedFirstFrame = false

		func attach(to view: MTKView) {
			self.view = view
			view.delegate = self
			guard let device = view.device else { return }
			commandQueue = device.makeCommandQueue()
			let library = device.makeDefaultLibrary()
			let descriptor = MTLRenderPipelineDescriptor()
			descriptor.vertexFunction = library?.makeFunction(name: "livePhotoVertex")
			descriptor.fragmentFunction = library?.makeFunction(name: "livePhotoFragment")
			descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
			descriptor.colorAttachments[0].isBlendingEnabled = true
			descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
			descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
			pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor)
			let samplerDescriptor = MTLSamplerDescriptor()
			samplerDescriptor.minFilter = .linear
			samplerDescriptor.magFilter = .linear
			samplerDescriptor.sAddressMode = .clampToEdge
			samplerDescriptor.tAddressMode = .clampToEdge
			samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
			CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
		}

		func update(
			id: String,
			movieURL: URL,
			isPlaying: Bool,
			contentSize: CGSize,
			placements: [PuzzleTilePresentation],
			didRenderFirstFrame: @escaping () -> Void
		) {
			self.didRenderFirstFrame = didRenderFirstFrame
			let now = CACurrentMediaTime()
			let previousAnimations = placementAnimations
			placementOrder = placements.map(\.id)
			placementAnimations = Dictionary(uniqueKeysWithValues: placements.map { placement in
				let previous = previousAnimations[placement.id]
				if let previous, previous.to == placement {
					return (placement.id, previous)
				}
				let current = previous?.value(at: now) ?? placement
				return (
					placement.id,
					PlacementAnimation(from: current, to: placement, startTime: now)
				)
			})
			self.contentSize = contentSize

			if currentID != id {
				configurePlayer(id: id, movieURL: movieURL)
			}

			guard self.isPlaying != isPlaying else { return }
			self.isPlaying = isPlaying
			if isPlaying {
				reportedFirstFrame = false
				lastPixelBuffer = nil
				if isPrerolled {
					player?.play()
				}
			} else {
				player?.pause()
			}
		}

		private func configurePlayer(id: String, movieURL: URL) {
			stopPlayer()
			currentID = id
			reportedFirstFrame = false
			isPrerolled = false
			visibleTextureRect = nil
			let asset = AVURLAsset(url: movieURL)
			let item = AVPlayerItem(asset: asset)
			let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
				kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
			])
			item.add(output)
			let pending = PendingPlayerConfiguration(id: id, item: item, output: output)
			AVVideoComposition.videoComposition(withPropertiesOf: asset) { [weak self] composition, _ in
				Task { @MainActor in
					guard let self, self.currentID == pending.id else { return }
					pending.item.videoComposition = composition
					self.finishConfiguringPlayer(item: pending.item, output: pending.output)
				}
			}
		}

		private func finishConfiguringPlayer(
			item: AVPlayerItem,
			output: AVPlayerItemVideoOutput
		) {
			statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] _, _ in
				Task { @MainActor in
					guard let self, let item, self.playerItem === item else { return }
					switch item.status {
					case .readyToPlay:
						self.preroll(item: item)
					case .failed:
						self.player?.pause()
					case .unknown:
						break
					@unknown default:
						break
					}
				}
			}
			let player = AVPlayer(playerItem: item)
			player.isMuted = true
			player.actionAtItemEnd = .none
			endObserver = NotificationCenter.default.addObserver(
				forName: .AVPlayerItemDidPlayToEndTime,
				object: item,
				queue: .main
			) { [weak self, weak player] _ in
				Task { @MainActor in
					guard let self, self.isPlaying else { return }
					player?.seek(to: .zero)
					player?.play()
				}
			}
			playerItem = item
			videoOutput = output
			self.player = player
			if item.status == .readyToPlay {
				preroll(item: item)
			}
		}

		private func preroll(item: AVPlayerItem) {
			guard !isPrerolled, playerItem === item, let player else { return }
			player.pause()
			player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak player] finished in
				Task { @MainActor in
					guard finished,
						  let self,
						  let player,
						  self.player === player,
						  self.playerItem === item else { return }
					player.preroll(atRate: 1) { [weak self, weak player] finished in
						Task { @MainActor in
							guard finished,
								  let self,
								  let player,
								  self.player === player,
								  self.playerItem === item else { return }
							self.isPrerolled = true
							self.lastPixelBuffer = nil
							self.reportedFirstFrame = false
							if self.isPlaying {
								player.play()
							}
						}
					}
				}
			}
		}

		func stop() {
			stopPlayer()
			view?.delegate = nil
		}

		private func stopPlayer() {
			statusObservation = nil
			player?.cancelPendingPrerolls()
			player?.pause()
			if let endObserver {
				NotificationCenter.default.removeObserver(endObserver)
			}
			endObserver = nil
			player = nil
			playerItem = nil
			videoOutput = nil
			lastPixelBuffer = nil
			visibleTextureRect = nil
			isPrerolled = false
			currentID = nil
		}

		func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
		}

		func draw(in view: MTKView) {
			drawFrame(in: view)
		}

		private func drawFrame(in view: MTKView) {
			let viewSize = view.bounds.size
			guard let drawable = view.currentDrawable,
				  let renderPassDescriptor = view.currentRenderPassDescriptor,
				  let commandQueue,
				  let pipelineState,
				  let textureCache,
				  viewSize.width > 0,
				  viewSize.height > 0 else { return }

			if let videoOutput, let playerItem {
				let itemTime = videoOutput.itemTime(forHostTime: CACurrentMediaTime())
				if videoOutput.hasNewPixelBuffer(forItemTime: itemTime),
				   let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) {
					lastPixelBuffer = pixelBuffer
					if visibleTextureRect == nil {
						visibleTextureRect = Self.detectVisibleContentRect(in: pixelBuffer)
					}
				}
				if playerItem.status == .failed {
					player?.pause()
				}
			}
			guard let pixelBuffer = lastPixelBuffer else { return }

			let textureWidth = CVPixelBufferGetWidth(pixelBuffer)
			let textureHeight = CVPixelBufferGetHeight(pixelBuffer)
			var cvTexture: CVMetalTexture?
			guard CVMetalTextureCacheCreateTextureFromImage(
				nil,
				textureCache,
				pixelBuffer,
				nil,
				.bgra8Unorm,
				textureWidth,
				textureHeight,
				0,
				&cvTexture
			) == kCVReturnSuccess,
				  let cvTexture,
				  let texture = CVMetalTextureGetTexture(cvTexture) else { return }

			let instances = makeTileInstances()
			let instanceDataLength = MemoryLayout<TileInstance>.stride * instances.count
			guard !instances.isEmpty,
				  let device = view.device,
				  let instanceBuffer = instanceBuffer(
					  for: instances,
					  byteCount: instanceDataLength,
					  device: device
				  ),
				  let commandBuffer = commandQueue.makeCommandBuffer(),
				  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }

			encoder.setRenderPipelineState(pipelineState)
			encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 0)
			let visibleRect = visibleTextureRect ?? CGRect(x: 0, y: 0, width: 1, height: 1)
			var frameUniforms = FrameUniforms(
				viewAndContentSize: SIMD4(
					Float(viewSize.width),
					Float(viewSize.height),
					Float(contentSize.width),
					Float(contentSize.height)
				),
				textureAndDrawableSize: SIMD4(
					Float(textureWidth),
					Float(textureHeight),
					Float(view.drawableSize.width),
					Float(view.drawableSize.height)
				),
				visibleTextureRect: SIMD4(
					Float(visibleRect.minX),
					Float(visibleRect.minY),
					Float(visibleRect.width),
					Float(visibleRect.height)
				)
			)
			encoder.setVertexBytes(
				&frameUniforms,
				length: MemoryLayout<FrameUniforms>.stride,
				index: 1
			)
			encoder.setFragmentTexture(texture, index: 0)
			if let samplerState {
				encoder.setFragmentSamplerState(samplerState, index: 0)
			}
			encoder.drawPrimitives(
				type: .triangle,
				vertexStart: 0,
				vertexCount: 6,
				instanceCount: instances.count
			)
			encoder.endEncoding()
			commandBuffer.present(drawable)
			commandBuffer.commit()
			if isPrerolled, !reportedFirstFrame {
				reportedFirstFrame = true
				didRenderFirstFrame?()
			}
		}

		private func instanceBuffer(
			for instances: [TileInstance],
			byteCount: Int,
			device: MTLDevice
		) -> MTLBuffer? {
			if instanceBuffers.count != 3 || instanceBuffers.contains(where: { $0.length < byteCount }) {
				let capacity = max(byteCount, instanceBuffers.map(\.length).max() ?? 0)
				instanceBuffers = (0..<3).compactMap { _ in
					device.makeBuffer(length: capacity, options: .storageModeShared)
				}
				instanceBufferIndex = 0
			}
			guard instanceBuffers.count == 3 else { return nil }
			let buffer = instanceBuffers[instanceBufferIndex]
			instanceBufferIndex = (instanceBufferIndex + 1) % instanceBuffers.count
			instances.withUnsafeBytes { bytes in
				guard let baseAddress = bytes.baseAddress else { return }
				buffer.contents().copyMemory(from: baseAddress, byteCount: byteCount)
			}
			return buffer
		}

		private static func detectVisibleContentRect(in pixelBuffer: CVPixelBuffer) -> CGRect {
			switch LivePhotoBoardRenderer.contentCropStrategy {
			case .fullFrame:
				return CGRect(x: 0, y: 0, width: 1, height: 1)
			case .darkPixelEdges:
				return darkPixelVisibleContentRect(in: pixelBuffer)
			}
		}

		private static func darkPixelVisibleContentRect(in pixelBuffer: CVPixelBuffer) -> CGRect {
			guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess,
				  let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
				return CGRect(x: 0, y: 0, width: 1, height: 1)
			}
			defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

			let width = CVPixelBufferGetWidth(pixelBuffer)
			let height = CVPixelBufferGetHeight(pixelBuffer)
			let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
			let pixels = baseAddress.assumingMemoryBound(to: UInt8.self)
			let horizontalSampleStride = max(1, width / 256)
			let verticalSampleStride = max(1, height / 256)

			func rowImageCoverage(_ y: Int) -> Double {
				let row = pixels.advanced(by: y * bytesPerRow)
				var imageSamples = 0
				var sampleCount = 0
				for x in stride(from: 0, to: width, by: horizontalSampleStride) {
					sampleCount += 1
					let pixel = row.advanced(by: x * 4)
					if Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2]) > 24 {
						imageSamples += 1
					}
				}
				return Double(imageSamples) / Double(sampleCount)
			}

			func columnImageCoverage(_ x: Int, from top: Int, to bottom: Int) -> Double {
				var imageSamples = 0
				var sampleCount = 0
				for y in stride(from: top, to: bottom, by: verticalSampleStride) {
					sampleCount += 1
					let pixel = pixels.advanced(by: y * bytesPerRow + x * 4)
					if Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2]) > 24 {
						imageSamples += 1
					}
				}
				return sampleCount > 0 ? Double(imageSamples) / Double(sampleCount) : 0
			}

			let maximumVerticalCrop = height / 5
			let maximumHorizontalCrop = width / 5
			let minimumImageCoverage = 0.25
			let top = (0..<maximumVerticalCrop).first {
				rowImageCoverage($0) >= minimumImageCoverage
			} ?? 0
			let bottomPadding = (0..<maximumVerticalCrop).first {
				rowImageCoverage(height - 1 - $0) >= minimumImageCoverage
			} ?? 0
			let bottom = height - bottomPadding
			let left = (0..<maximumHorizontalCrop).first {
				columnImageCoverage($0, from: top, to: bottom) >= minimumImageCoverage
			} ?? 0
			let rightPadding = (0..<maximumHorizontalCrop).first {
				columnImageCoverage(width - 1 - $0, from: top, to: bottom) >= minimumImageCoverage
			} ?? 0
			let visibleWidth = width - left - rightPadding
			let visibleHeight = height - top - bottomPadding
			guard visibleWidth >= width * 3 / 5, visibleHeight >= height * 3 / 5 else {
				return CGRect(x: 0, y: 0, width: 1, height: 1)
			}
			return CGRect(
				x: CGFloat(left) / CGFloat(width),
				y: CGFloat(top) / CGFloat(height),
				width: CGFloat(visibleWidth) / CGFloat(width),
				height: CGFloat(visibleHeight) / CGFloat(height)
			)
		}

		private func makeTileInstances() -> [TileInstance] {
			let now = CACurrentMediaTime()
			let placements = placementOrder.compactMap { placementAnimations[$0]?.value(at: now) }
			guard contentSize.width > 0, contentSize.height > 0 else { return [] }
			return placements.compactMap { placement in
				// The open tile is logically part of the board but must not submit a
				// drawable quad. Skipping it also avoids transparent RGB content being
				// exposed by platform compositor differences.
				guard placement.opacity > 0.001 else { return nil }
				let rect = placement.destinationRect
				let source = placement.sourceRect
				return TileInstance(
					destinationRect: SIMD4(
						Float(rect.minX),
						Float(rect.minY),
						Float(rect.width),
						Float(rect.height)
					),
					sourceRect: SIMD4(
						Float(source.minX),
						Float(source.minY),
						Float(source.maxX),
						Float(source.maxY)
					),
					borderColor: placement.borderColor,
					cornerRadius: placement.cornerRadius,
					opacity: placement.opacity,
					contentInset: placement.contentInset,
					borderWidth: placement.borderWidth
				)
			}
		}
	}
}
