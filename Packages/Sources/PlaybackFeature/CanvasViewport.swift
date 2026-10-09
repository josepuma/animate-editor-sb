import CoreGraphics

/// How the canvas is looked at: how close, and centred where.
///
/// Zoomed out, what lies off the stage shows around it — a sprite parked
/// outside the frame, or a selection frame larger than the stage, whole and
/// with its corners in reach. Zoomed in, detail. None of it reaches the
/// storyboard: the stage is what osu! draws, and this is only the window onto
/// the canvas it sits in.
///
/// Canvas units are the renderer's: storyboard x plus the stage's offset, so
/// the stage runs from `0` to its width. Pure, so the mapping every overlay
/// and the renderer share can be tested without a window.
public struct CanvasViewport: Sendable, Equatable {
    /// 1 is the stage fitted to the space it is given — what the canvas has
    /// always shown. Below it, more canvas around the stage; above, closer.
    public var zoom: Double

    /// The canvas point at the middle of the view, or `nil` for the stage's
    /// own centre.
    public var centre: CGPoint?

    public static let minimumZoom = 0.25
    public static let maximumZoom = 4.0

    /// What the zoom menu offers.
    public static let presets: [Double] = [0.25, 0.5, 0.75, 1, 1.5, 2, 4]

    public init(zoom: Double = 1, centre: CGPoint? = nil) {
        self.zoom = zoom
        self.centre = centre
    }

    /// Where everything sits for one container.
    public struct Layout: Sendable, Equatable {
        /// Where the stage is drawn, in the container's coordinates. Larger
        /// than the container when zoomed in, smaller when out.
        public let stageRect: CGRect
        /// Points on screen per canvas unit.
        public let pointsPerUnit: Double
        /// The part of the canvas the container shows, in canvas units.
        public let visible: CGRect

        public func canvasPoint(atView point: CGPoint) -> CGPoint {
            CGPoint(
                x: (point.x - stageRect.minX) / pointsPerUnit,
                y: (point.y - stageRect.minY) / pointsPerUnit,
            )
        }

        public func viewPoint(ofCanvas point: CGPoint) -> CGPoint {
            CGPoint(
                x: stageRect.minX + point.x * pointsPerUnit,
                y: stageRect.minY + point.y * pointsPerUnit,
            )
        }
    }

    public func layout(container: CGSize, stage: CGSize) -> Layout {
        let fit = Self.fit(container: container, stage: stage)
        let scale = fit * zoom
        let centre = centre ?? CGPoint(x: stage.width / 2, y: stage.height / 2)
        let stageRect = CGRect(
            x: container.width / 2 - centre.x * scale,
            y: container.height / 2 - centre.y * scale,
            width: stage.width * scale,
            height: stage.height * scale,
        )
        let visible = CGRect(
            x: centre.x - container.width / 2 / scale,
            y: centre.y - container.height / 2 / scale,
            width: container.width / scale,
            height: container.height / scale,
        )
        return Layout(stageRect: stageRect, pointsPerUnit: scale, visible: visible)
    }

    /// Zooms so the canvas point under `viewPoint` stays under it.
    ///
    /// Toward the middle of the view instead, a sprite in a corner being
    /// zoomed onto runs off the screen just as it is looked at.
    public mutating func zoom(
        to newZoom: Double,
        keeping viewPoint: CGPoint,
        container: CGSize,
        stage: CGSize,
    ) {
        let anchor = layout(container: container, stage: stage).canvasPoint(atView: viewPoint)
        zoom = min(max(newZoom, Self.minimumZoom), Self.maximumZoom)
        let scale = Self.fit(container: container, stage: stage) * zoom
        centre = CGPoint(
            x: anchor.x - (viewPoint.x - container.width / 2) / scale,
            y: anchor.y - (viewPoint.y - container.height / 2) / scale,
        )
        clampCentre(stage: stage)
    }

    /// Moves the picture by `delta` view points, the way a hand drags it.
    public mutating func pan(by delta: CGSize, container: CGSize, stage: CGSize) {
        let scale = Self.fit(container: container, stage: stage) * zoom
        let current = centre ?? CGPoint(x: stage.width / 2, y: stage.height / 2)
        centre = CGPoint(x: current.x - delta.width / scale, y: current.y - delta.height / scale)
        clampCentre(stage: stage)
    }

    /// Back to the stage fitted and centred.
    public mutating func fit() {
        self = CanvasViewport()
    }

    /// Whether this is the plain fitted view, which every control treats as
    /// "not zoomed".
    public var isFitted: Bool { zoom == 1 && centre == nil }

    /// Keeps the middle of the view on the stage, so the stage can never be
    /// panned out of sight and lost.
    private mutating func clampCentre(stage: CGSize) {
        guard let centre else { return }
        self.centre = CGPoint(
            x: min(max(centre.x, 0), stage.width),
            y: min(max(centre.y, 0), stage.height),
        )
    }

    private static func fit(container: CGSize, stage: CGSize) -> Double {
        guard stage.width > 0, stage.height > 0 else { return 1 }
        return max(0.0001, min(container.width / stage.width, container.height / stage.height))
    }
}
