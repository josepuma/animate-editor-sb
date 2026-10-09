import AVFoundation
import Foundation

/// What the app needs to know about an audio file without playing it.
public enum AudioFileInfo {
    /// The file's length in seconds, or `nil` when it cannot be read.
    ///
    /// Core cannot open a file, so a sample clip's length arrives through a
    /// seam the app fills with this. `nil` is an answer, not an error: an
    /// undecodable file (an ogg this platform cannot open, say) still gets
    /// placed, with the fallback length.
    public static func duration(of url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let rate = file.processingFormat.sampleRate
        guard rate > 0, file.length > 0 else { return nil }
        return Double(file.length) / rate
    }
}
