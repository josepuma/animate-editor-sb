import AVFoundation
import CoreMedia
import Foundation
import Testing

@testable import StoryboardRendering

/// The sound in an exported video lines up with the picture.
///
/// Reported as "the exported video's audio is out of sync". The video is
/// written from zero — frame 0 at time 0 — and covers only the stretch with
/// something on screen, which rarely starts at the top of the song. The audio
/// was read from that same stretch, but `AVAssetReader` hands samples back
/// stamped with the FILE's times: a storyboard starting at 30s had its first
/// sample stamped 30s, and the writer put it 30s into the video. The sound ran
/// late by exactly how long the song played before the storyboard began.
///
/// Tested without a GPU — the export's picture needs one and CI has none — by
/// pulling the two decisions that were wrong out as pure functions.
@Suite("Video export audio")
struct VideoExportAudioTests {
    /// A short buffer of silent PCM stamped at `seconds`.
    private func sample(at seconds: Double) throws -> CMSampleBuffer {
        var description = AudioStreamBasicDescription(
            mSampleRate: 44_100, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 2, mBitsPerChannel: 16, mReserved: 0,
        )
        var format: CMAudioFormatDescription?
        #expect(CMAudioFormatDescriptionCreate(
            allocator: nil, asbd: &description, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format,
        ) == noErr)

        let frames = 441
        var block: CMBlockBuffer?
        #expect(CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: frames * 4, blockAllocator: nil,
            customBlockSource: nil, offsetToData: 0, dataLength: frames * 4, flags: 0, blockBufferOut: &block,
        ) == noErr)
        _ = CMBlockBufferFillDataBytes(with: 0, blockBuffer: block!, offsetIntoDestination: 0, dataLength: frames * 4)

        var buffer: CMSampleBuffer?
        #expect(CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block!, formatDescription: format!, sampleCount: frames,
            presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 44_100),
            packetDescriptions: nil, sampleBufferOut: &buffer,
        ) == noErr)
        return try #require(buffer)
    }

    private func seconds(_ buffer: CMSampleBuffer) -> Double {
        CMSampleBufferGetPresentationTimeStamp(buffer).seconds
    }

    /// The bug itself: a stretch starting 30s into the song has its first
    /// sample land at the video's zero, not 30s into it.
    @Test("sound read from later in the song lands at the start of the video")
    func laterStretchStartsAtZero() throws {
        let moved = try #require(VideoExport.retimed(try sample(at: 30), subtracting: 30_000))
        #expect(abs(seconds(moved)) < 0.001, "the first sample sits at \(seconds(moved))s")

        let later = try #require(VideoExport.retimed(try sample(at: 31.5), subtracting: 30_000))
        #expect(abs(seconds(later) - 1.5) < 0.001, "and the rest keep their spacing: \(seconds(later))s")
    }

    /// A storyboard can open before the song does. The picture starts then;
    /// the sound has to wait until its own zero comes round in the video.
    @Test("a storyboard opening before the song delays the sound")
    func earlyStartDelaysSound() throws {
        let moved = try #require(VideoExport.retimed(try sample(at: 0), subtracting: -2000))
        #expect(abs(seconds(moved) - 2) < 0.001, "the song's first sample sits at \(seconds(moved))s")
    }

    /// There is nothing before the song to read: the reader starts at zero.
    @Test("the stretch read from the file never starts before the song")
    func readRangeStartsAtZero() {
        let early = VideoExport.audioRange(for: -2000 ... 5000)
        #expect(early.start.seconds == 0)
        #expect(abs(early.duration.seconds - 5) < 0.001)

        let later = VideoExport.audioRange(for: 30_000 ... 38_000)
        #expect(abs(later.start.seconds - 30) < 0.001)
        #expect(abs(later.duration.seconds - 8) < 0.001)
    }
}
