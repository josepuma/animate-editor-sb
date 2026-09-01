import AVFoundation
import CoreVideo
import Foundation
import Metal
import StoryboardCore

/// Renders a storyboard to a video file.
///
/// Frame by frame, as fast as the GPU manages rather than in real time: a
/// minute of storyboard is 3,600 frames at 60fps, and nothing is watching them
/// go by. Waiting for a clock would make the export take exactly as long as the
/// piece, for no gain at all.
///
/// The renderer already draws a frame for any moment — `resolve(at:)` is a pure
/// function of time — so this is mostly plumbing: draw into a texture, copy it
/// into a pixel buffer, hand it to `AVAssetWriter`.
/// On the main actor because the renderer is.
///
/// It shares the editor's renderer rather than building a second one: an atlas
/// is tens of megabytes and the sprites are already uploaded. The cost is that
/// an export holds the main thread between frames — which is why it `await`s,
/// giving the interface a turn to draw its progress.
@MainActor
public final class VideoExport {
    public struct Settings: Sendable {
        /// Frames per second in the written file.
        public var frameRate: Int
        /// How much larger than the stage to render.
        ///
        /// How much larger than the stage to render.
        ///
        /// The stage is 854×480, and a sprite drawn there is already smaller
        /// than the texture behind it — a 512px particle covers a fraction of
        /// that frame. Rendering at a multiple lets those textures be sampled
        /// closer to their own resolution instead of being squeezed into half a
        /// megapixel, so detail that exists in the artwork survives.
        ///
        /// It is also what stops the encoder from mangling the picture: a
        /// storyboard is mostly soft gradients and particle fields, which are
        /// the hardest thing for H.264 to keep clean at a small frame size.
        public var scale: Int
        /// Average bitrate.
        ///
        /// Generous on purpose. A storyboard is gradients, glows and additive
        /// particle fields — the three things H.264 bands and smears first, and
        /// exactly what a default bitrate spends its budget badly on. Disk is
        /// cheaper than re-rendering.
        public var bitrate: Int

        public init(frameRate: Int = 60, scale: Int = 2, bitrate: Int = 40_000_000) {
            self.frameRate = frameRate
            self.scale = scale
            self.bitrate = bitrate
        }

        public static let standard = Settings()
    }

    public enum Failure: Error, CustomStringConvertible {
        case textureCreationFailed
        case pixelBufferCreationFailed
        case writerCreationFailed(String)
        case writeFailed(String)

        public var description: String {
            switch self {
            case .textureCreationFailed: "Could not make a render target."
            case .pixelBufferCreationFailed: "Could not make a frame buffer."
            case let .writerCreationFailed(reason): "Could not start writing: \(reason)"
            case let .writeFailed(reason): "Writing failed: \(reason)"
            }
        }
    }

    private let renderer: MetalStoryboardRenderer
    private let device: MTLDevice
    private let settings: Settings

    public init(
        renderer: MetalStoryboardRenderer,
        device: MTLDevice,
        settings: Settings = .standard,
    ) {
        self.renderer = renderer
        self.device = device
        self.settings = settings
    }

    /// Writes `range` of the storyboard to `url`.
    ///
    /// - Parameter progress: called with a fraction from 0 to 1. An export runs
    ///   for minutes, and one that says nothing is one people assume has hung.
    /// - Parameter audio: the track to lay under the picture, if there is one.
    ///   The same stretch as the video, so the two line up without an offset to
    ///   remember.
    public func write(
        range: ClosedRange<Double>,
        to url: URL,
        audio: URL? = nil,
        progress: @escaping @Sendable (Double) -> Void = { _ in },
    ) async throws {
        let size = frameSize()
        let writer = try makeWriter(url: url, size: size)
        let input = makeInput(size: size)
        let adaptor = makeAdaptor(for: input, size: size)

        writer.add(input)

        // Added before writing begins.
        //
        // `AVAssetWriter` takes no more inputs once `startWriting` has been
        // called, so an audio track added later was silently refused — the
        // video came out mute with no error to show for it.
        var sound: Sound?
        if let audio { sound = try await makeAudio(from: audio, range: range) }
        if let sound, writer.canAdd(sound.input) {
            writer.add(sound.input)
        }

        guard writer.startWriting() else {
            throw Failure.writerCreationFailed(writer.error?.localizedDescription ?? "unknown")
        }
        writer.startSession(atSourceTime: .zero)

        guard let texture = makeTexture(size: size) else {
            throw Failure.textureCreationFailed
        }

        let frameCount = max(1, Int((range.upperBound - range.lowerBound)
            / 1000 * Double(settings.frameRate)))
        let step = 1000.0 / Double(settings.frameRate)

        for frame in 0..<frameCount {
            let time = range.lowerBound + Double(frame) * step
            renderer.render(at: time, into: texture)

            guard let buffer = adaptor.pixelBufferPool
                .flatMap({ pool -> CVPixelBuffer? in
                    var buffer: CVPixelBuffer?
                    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                    return buffer
                })
            else { throw Failure.pixelBufferCreationFailed }

            copy(texture: texture, into: buffer)

            // Waited on rather than dropped: `isReadyForMoreMediaData` going
            // false means the writer is behind, and a frame appended anyway is
            // a frame silently lost from the middle of the video.
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }

            let presentation = CMTime(
                value: CMTimeValue(frame),
                timescale: CMTimeScale(settings.frameRate),
            )
            guard adaptor.append(buffer, withPresentationTime: presentation) else {
                throw Failure.writeFailed(writer.error?.localizedDescription ?? "append failed")
            }

            progress(Double(frame + 1) / Double(frameCount))

            // Handed back regularly, not only when the writer is behind.
            //
            // This runs on the main actor — it shares the editor's renderer —
            // and an `await` that never suspends never lets the interface draw.
            // Nineteen thousand frames went by with the window frozen and the
            // progress stuck at nought, while the file grew perfectly well.
            if frame % 4 == 0 { await Task.yield() }

            // Stopping is the author's to decide: an export of a long track is
            // minutes of work, and one that cannot be called off is one nobody
            // starts.
            try Task.checkCancellation()
        }

        input.markAsFinished()

        if let sound {
            sound.reader.startReading()
            await feed(sound)
        }

        await writer.finishWriting()

        if writer.status == .failed {
            throw Failure.writeFailed(writer.error?.localizedDescription ?? "unknown")
        }
    }

    // ─── Pieces ──────────────────────────────────────────────────────────────

    private func frameSize() -> (width: Int, height: Int) {
        let stage = OsuCanvas.size(widescreen: renderer.isWidescreen)
        // Even dimensions: H.264 encodes in macroblocks and an odd side is
        // rounded by the encoder, which shifts every pixel by half of one.
        let width = Int(stage.width) * settings.scale
        let height = Int(stage.height) * settings.scale
        return (width - width % 2, height - height % 2)
    }

    private func makeTexture(size: (width: Int, height: Int)) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            // BGRA, which is what a pixel buffer wants — not the atlas's RGBA.
            //
            // `getBytes` copies bytes without reordering them, so a texture
            // rendered RGBA read into a BGRA buffer swaps red and blue: fire
            // exported blue. The shader writes whatever the target asks for, so
            // rendering straight into BGRA costs nothing and needs no
            // conversion pass. It is also what the on-screen view uses.
            pixelFormat: .bgra8Unorm,
            width: size.width,
            height: size.height,
            mipmapped: false,
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        // Shared, so the CPU can read it back without a blit to a staging
        // buffer — an export copies every frame, and a private texture would
        // mean a second copy of each.
        descriptor.storageMode = .shared
        return device.makeTexture(descriptor: descriptor)
    }

    private func makeWriter(url: URL, size: (width: Int, height: Int)) throws -> AVAssetWriter {
        try? FileManager.default.removeItem(at: url)
        do {
            return try AVAssetWriter(outputURL: url, fileType: .mp4)
        } catch {
            throw Failure.writerCreationFailed(error.localizedDescription)
        }
    }

    private func makeInput(size: (width: Int, height: Int)) -> AVAssetWriterInput {
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: settings.bitrate,
                AVVideoMaxKeyFrameIntervalKey: settings.frameRate * 2,
            ],
        ])
        // Frames arrive in order and on demand, so the writer need not buffer
        // for a source that might jump about.
        input.expectsMediaDataInRealTime = false
        return input
    }

    private func makeAdaptor(
        for input: AVAssetWriterInput,
        size: (width: Int, height: Int),
    ) -> AVAssetWriterInputPixelBufferAdaptor {
        AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: size.width,
                kCVPixelBufferHeightKey as String: size.height,
                kCVPixelBufferMetalCompatibilityKey as String: true,
            ],
        )
    }

    /// Copies the rendered texture into a pixel buffer, row by row.
    ///
    /// Row by row because the two rarely agree on stride: a pixel buffer pads
    /// each row out to an alignment the encoder likes, and copying the whole
    /// block in one go would shear the picture diagonally.
    private func copy(texture: MTLTexture, into buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let destination = CVPixelBufferGetBaseAddress(buffer) else { return }
        let destinationStride = CVPixelBufferGetBytesPerRow(buffer)
        let sourceStride = texture.width * 4

        texture.getBytes(
            destination,
            bytesPerRow: destinationStride,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0,
        )
        _ = sourceStride
    }
}


// ─── Sound ───────────────────────────────────────────────────────────────────

extension VideoExport {
    /// An audio input and the reader that will fill it.
    struct Sound {
        let input: AVAssetWriterInput
        let reader: AVAssetReader
        let output: AVAssetReaderTrackOutput
    }

    /// Prepares the track's audio, without starting to read it.
    ///
    /// Built before the writer starts because that is the only time it will
    /// accept an input, and read afterwards because that is the only time a
    /// sample can be appended.
    private func makeAudio(from url: URL, range: ClosedRange<Double>) async throws -> Sound? {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            return nil
        }

        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44_100,
            AVEncoderBitRateKey: 192_000,
        ])
        input.expectsMediaDataInRealTime = false

        let reader = try AVAssetReader(asset: asset)
        // The same stretch the video covers, so the sound starts where the
        // picture does — a storyboard rarely begins at the top of the track.
        reader.timeRange = CMTimeRange(
            start: CMTime(value: CMTimeValue(range.lowerBound), timescale: 1_000),
            duration: CMTime(
                value: CMTimeValue(range.upperBound - range.lowerBound),
                timescale: 1_000,
            ),
        )

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
        ])
        guard reader.canAdd(output) else { return nil }
        reader.add(output)

        return Sound(input: input, reader: reader, output: output)
    }

    /// Pumps every sample from the reader into the writer.
    private func feed(_ sound: Sound) async {
        await withCheckedContinuation { continuation in
            sound.input.requestMediaDataWhenReady(on: .global(qos: .userInitiated)) {
                while sound.input.isReadyForMoreMediaData {
                    guard let buffer = sound.output.copyNextSampleBuffer() else {
                        sound.input.markAsFinished()
                        continuation.resume()
                        return
                    }
                    sound.input.append(buffer)
                }
            }
        }
    }
}
