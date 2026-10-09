/// One sound the game plays at a moment of the song.
///
/// The `.osb` spells it `Sample,<time>,<layer>,"<path>",<volume>`. It lives
/// beside the sprites rather than inside one: a sample has no position, no
/// commands and no image, so modelling it as a sprite with nothing drawn would
/// hand every renderer a thing it has to remember to skip.
public struct StoryboardSample: Sendable, Equatable {
    /// Song time, in whole milliseconds: osu! rejects a decimal here as it does
    /// for command times.
    public var time: Double
    /// Which layer the sample belongs to. Only the four the format has: a
    /// sample cannot be in Overlay, and the parser and the collector both map
    /// it to Foreground.
    public var layer: Layer
    public var path: String
    /// 0...100.
    public var volume: Int

    public init(time: Double, layer: Layer, path: String, volume: Int) {
        self.time = time
        self.layer = layer
        self.path = path
        self.volume = volume
    }
}
