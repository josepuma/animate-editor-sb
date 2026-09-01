import Foundation
import Testing

@testable import StoryboardCore

@Suite("Track colour")
struct TrackColourTests {
    /// Optional rather than defaulted, so "never chosen" and "chosen to match
    /// the layer" stay different: a track without one follows its layer when
    /// that layer changes, and one with a colour keeps it.
    @Test("a new track has no colour of its own")
    func newTracksFollowTheirLayer() {
        var document = EffectDocument()
        let track = document.addTrack()

        #expect(document.track(id: track.id)?.colour == nil)
    }

    @Test("a colour can be set and cleared")
    func colourRoundTrips() {
        var document = EffectDocument()
        let track = document.addTrack()

        document.setColour(.teal, on: track.id)
        #expect(document.track(id: track.id)?.colour == .teal)

        document.setColour(nil, on: track.id)
        #expect(document.track(id: track.id)?.colour == nil)
    }

    /// A colour is part of the project, or it is lost the moment the file is
    /// closed.
    @Test("a colour survives a save and a load")
    func colourSurvivesTheFile() throws {
        var document = EffectDocument()
        let track = document.addTrack()
        document.setColour(.amber, on: track.id)

        let data = try JSONEncoder().encode(Project(document: document))
        let read = try JSONDecoder().decode(Project.self, from: data)

        #expect(read.document.tracks.first?.colour == .amber)
    }

    /// A file written before tracks could be coloured has to open unchanged
    /// rather than refusing to open at all.
    @Test("a project without colours still opens")
    func oldProjectsOpen() throws {
        let json = """
        {"formatVersion":1,"document":{"tracks":[
        {"id":"t1","name":"Effects","layer":"Foreground","nodes":[],
        "isVisible":true,"isLocked":false}]}}
        """
        let read = try JSONDecoder().decode(Project.self, from: Data(json.utf8))

        #expect(read.document.tracks.first?.colour == nil)
    }
}

@Suite("Saved timeline view")
struct SavedTimelineViewTests {
    /// Part of the project rather than of the app's preferences: it belongs to
    /// this storyboard, and reopening one to find the view somewhere else means
    /// finding your place again every time.
    @Test("the timeline window survives a save and a load")
    func viewSurvivesTheFile() throws {
        let project = Project(
            document: EffectDocument(),
            view: .init(magnification: 8, start: 42_000),
        )

        let data = try JSONEncoder().encode(project)
        let read = try JSONDecoder().decode(Project.self, from: data)

        #expect(read.view?.magnification == 8)
        #expect(read.view?.start == 42_000)
    }

    @Test("a project without a saved view opens showing everything")
    func absentViewIsNil() throws {
        let data = try JSONEncoder().encode(Project(document: EffectDocument()))
        let read = try JSONDecoder().decode(Project.self, from: data)

        #expect(read.view == nil)
    }
}
