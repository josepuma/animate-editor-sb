import AVFoundation
import Foundation
import Testing

@testable import StoryboardPersistence

@Suite("Audio file info")
struct AudioFileInfoTests {
    private func writeAudio(seconds: Double) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("audio-info-\(UUID().uuidString).caf")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(seconds * 44_100)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        try file.write(from: buffer)
        return url
    }

    @Test("the duration is the file's own length")
    func duration() throws {
        let short = try writeAudio(seconds: 0.5)
        let long = try writeAudio(seconds: 2.5)
        defer { try? FileManager.default.removeItem(at: short); try? FileManager.default.removeItem(at: long) }

        let a = try #require(AudioFileInfo.duration(of: short))
        let b = try #require(AudioFileInfo.duration(of: long))
        #expect(abs(a - 0.5) < 0.01)
        #expect(abs(b - 2.5) < 0.01)
    }

    @Test("garbage and missing files have no duration")
    func unreadable() throws {
        let garbage = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("garbage-\(UUID().uuidString).wav")
        try Data([1, 2, 3, 4]).write(to: garbage)
        defer { try? FileManager.default.removeItem(at: garbage) }

        #expect(AudioFileInfo.duration(of: garbage) == nil)
        #expect(AudioFileInfo.duration(of: URL(fileURLWithPath: "/nonexistent/x.wav")) == nil)
    }
}
