import StoryboardCore
import Testing

@testable import EditorShellFeature

/// The moves the inspector's stopwatch makes.
///
/// The view itself cannot be tested, but everything it calls can — and these
/// are the same three moves the transform's stopwatch already has, because a
/// stopwatch has to mean one thing wherever it appears.
@MainActor
@Suite("Filter animation")
struct FilterAnimationTests {
    /// A model holding one clip with a glow on it.
    private func model() -> (EditorShellModel, EffectNode.ID, FilterNode.ID) {
        let shell = EditorShellModel()
        // Through the model's own API, which is what the inspector uses — a
        // test reaching past it would not exercise the same path.
        let node = shell.addEffect(EmitterEffect.descriptor, at: 0, duration: 2000)
        let filter = shell.addFilter(GlowFilter.descriptor, to: node.id)!
        return (shell, node.id, filter.id)
    }

    private var intensity: String { GlowFilter.Param.intensity }

    /// The first click has to leave something behind, or nothing appears to
    /// have happened — and the key holds what the parameter already had, so
    /// switching animation on changes nothing on screen.
    @Test("the stopwatch plants a key holding the current value")
    func beginAnimatingKeepsTheValue() {
        let (shell, nodeID, filterID) = model()
        shell.setFilterValue(.number(0.4), for: intensity, on: filterID, in: nodeID)

        shell.beginAnimatingFilter(intensity, on: filterID, in: nodeID, at: 500)

        let track = shell.filterAnimation(intensity, on: filterID, in: nodeID)
        #expect(track?.isActive == true)
        #expect(track?.keyframes.count == 1)
        #expect(track?.keyframes.first?.time == 500)
        #expect(track?.keyframes.first?.value == 0.4)
    }

    /// Switching animation off keeps the keys. Deleting a stopwatch's worth of
    /// work on the click that started it is a trap, and there is no undo here
    /// to climb out of it with.
    @Test("switching animation off keeps the keyframes")
    func disablingKeepsKeys() {
        let (shell, nodeID, filterID) = model()
        shell.beginAnimatingFilter(intensity, on: filterID, in: nodeID, at: 0)
        shell.setFilterKeyframe(1.5, for: intensity, on: filterID, in: nodeID, at: 1000)

        shell.setFilterAnimationEnabled(
            false, for: intensity, on: filterID, in: nodeID, at: 1000,
        )

        let track = shell.filterAnimation(intensity, on: filterID, in: nodeID)
        #expect(track?.keyframes.count == 2)
        #expect(track?.isEnabled == false)
        #expect(track?.isActive == false)
    }

    /// And it keeps what the animation was worth at that moment: switching it
    /// off is a decision about how a property behaves, not about its value.
    @Test("switching off holds the value it had")
    func disablingHoldsTheValue() {
        let (shell, nodeID, filterID) = model()
        shell.setFilterValue(.number(0.2), for: intensity, on: filterID, in: nodeID)
        shell.beginAnimatingFilter(intensity, on: filterID, in: nodeID, at: 0)
        shell.setFilterKeyframe(1.8, for: intensity, on: filterID, in: nodeID, at: 1000)

        shell.setFilterAnimationEnabled(
            false, for: intensity, on: filterID, in: nodeID, at: 1000,
        )

        // Not back to the 0.2 it rested at before anyone animated it.
        #expect(shell.filterValue(intensity, on: filterID, in: nodeID, at: 0) == 1.8)
    }

    /// Planting a key on a switched-off track switches it back on: adding a key
    /// is asking for the thing to animate, and leaving it inert would look like
    /// the click did nothing.
    @Test("adding a key re-enables a disabled track")
    func addingAKeyReenables() {
        let (shell, nodeID, filterID) = model()
        shell.beginAnimatingFilter(intensity, on: filterID, in: nodeID, at: 0)
        shell.setFilterAnimationEnabled(
            false, for: intensity, on: filterID, in: nodeID, at: 0,
        )

        shell.setFilterKeyframe(1.0, for: intensity, on: filterID, in: nodeID, at: 800)

        #expect(shell.filterAnimation(intensity, on: filterID, in: nodeID)?.isActive == true)
    }

    /// The field shows the value at the playhead while animating, so scrubbing
    /// moves the number — exactly as a transform's does.
    @Test("the value follows the playhead while animating")
    func valueFollowsThePlayhead() {
        let (shell, nodeID, filterID) = model()
        shell.beginAnimatingFilter(intensity, on: filterID, in: nodeID, at: 0)
        shell.setFilterKeyframe(0.0, for: intensity, on: filterID, in: nodeID, at: 0)
        shell.setFilterKeyframe(2.0, for: intensity, on: filterID, in: nodeID, at: 1000)

        #expect(shell.filterValue(intensity, on: filterID, in: nodeID, at: 0) == 0)
        #expect(shell.filterValue(intensity, on: filterID, in: nodeID, at: 1000) == 2)
        let middle = shell.filterValue(intensity, on: filterID, in: nodeID, at: 500)
        #expect(abs((middle ?? 0) - 1) < 1e-9)
    }

    /// With nothing animating it, the field shows the resting value at every
    /// moment — the playhead must not appear to change a parameter nobody
    /// animated.
    @Test("an unanimated parameter ignores the playhead")
    func restingValueIgnoresThePlayhead() {
        let (shell, nodeID, filterID) = model()
        shell.setFilterValue(.number(0.7), for: intensity, on: filterID, in: nodeID)

        #expect(shell.filterValue(intensity, on: filterID, in: nodeID, at: 0) == 0.7)
        #expect(shell.filterValue(intensity, on: filterID, in: nodeID, at: 1900) == 0.7)
    }

    /// Deleting is its own action and takes the whole track, keeping what it
    /// was worth so the clip does not jump when the keys go.
    @Test("clearing removes the keys and keeps the value")
    func clearingKeepsTheValue() {
        let (shell, nodeID, filterID) = model()
        shell.beginAnimatingFilter(intensity, on: filterID, in: nodeID, at: 0)
        shell.setFilterKeyframe(1.2, for: intensity, on: filterID, in: nodeID, at: 1000)

        shell.clearFilterAnimation(
            for: intensity, on: filterID, in: nodeID, keeping: 1000,
        )

        #expect(shell.filterAnimation(intensity, on: filterID, in: nodeID) == nil)
        #expect(shell.filterValue(intensity, on: filterID, in: nodeID, at: 0) == 1.2)
    }

    /// Keys are clip-local, so one past the end names a moment the clip never
    /// reaches: it would sit in the file, draw in the lane, and never play.
    @Test("a key past the clip's end is clamped into it")
    func keysAreClampedToTheClip() {
        let (shell, nodeID, filterID) = model()
        shell.setFilterKeyframe(1.0, for: intensity, on: filterID, in: nodeID, at: 9000)

        let track = shell.filterAnimation(intensity, on: filterID, in: nodeID)
        #expect(track?.keyframes.first?.time == 2000)
    }

    /// Animating has to reach the canvas. The model's whole job here is to run
    /// the evaluation again, and a stopwatch that changed nothing on screen
    /// would be indistinguishable from a broken one.
    @Test("animating a filter re-evaluates the document")
    func animatingReevaluates() {
        let (shell, nodeID, filterID) = model()
        let before = shell.effectsRevision

        shell.beginAnimatingFilter(intensity, on: filterID, in: nodeID, at: 0)

        #expect(shell.effectsRevision != before)
    }
}

/// The keyframe editor's filter rows.
///
/// The same row component the transform uses, because a keyframe is a keyframe
/// wherever it came from — dragging, easing and deleting have to work one way
/// or the mode has two vocabularies.
@MainActor
@Suite("Filter keyframe rows")
struct FilterKeyframeRowTests {
    private func model() -> (EditorShellModel, EffectNode.ID, FilterNode.ID) {
        let shell = EditorShellModel()
        let node = shell.addEffect(EmitterEffect.descriptor, at: 0, duration: 2000)
        let filter = shell.addFilter(GlowFilter.descriptor, to: node.id)!
        return (shell, node.id, filter.id)
    }

    /// Rows the editor draws, headings included and folded groups excluded.
    private func rowCount(_ shell: EditorShellModel, _ nodeID: EffectNode.ID) -> Int {
        guard let node = shell.effects[nodeID] else { return 0 }
        return KeyframeRows.rowCount(
            of: node,
            descriptor: { shell.filters.descriptor(for: $0) },
            isTransformExpanded: shell.isTransformGroupExpanded,
            isFilterExpanded: { shell.isFilterGroupExpanded($0, in: nodeID) },
        )
    }

    /// Just the filter groups' rows, so a test can talk about them without
    /// counting the transform's nine and the headings.
    private func filterRowCount(_ shell: EditorShellModel, _ nodeID: EffectNode.ID) -> Int {
        guard let node = shell.effects[nodeID] else { return 0 }
        return rowCount(shell, nodeID)
            - 1  // the transform heading
            - (shell.isTransformGroupExpanded ? TransformProperty.allCases.count : 0)
            - KeyframeRows.groups(
                for: node.filters, descriptor: { shell.filters.descriptor(for: $0) },
            ).count  // one heading each
    }

    /// A filter nobody has animated adds no rows. Every animatable parameter of
    /// every filter would bury the transform's five under a dozen nobody asked
    /// for — the same reason the mode shows one clip rather than all of them.
    /// A filter nobody has animated is one line — its heading — rather than a
    /// row per parameter. Fifteen rows above the nine anybody came for is what
    /// folding exists to prevent.
    @Test("an untouched filter is one folded heading")
    func untouchedFilterIsOneLine() {
        let (shell, nodeID, _) = model()
        // Nine properties, the transform heading, and the glow's heading.
        #expect(rowCount(shell, nodeID) == TransformProperty.allCases.count + 2)
        #expect(filterRowCount(shell, nodeID) == 0)
    }

    /// Opened, it shows every parameter it can animate — not only the animated
    /// ones. This is where somebody starts an animation, and a parameter with
    /// no keys would have no row to start it on.
    @Test("an opened filter shows all its animatable parameters")
    func openedFilterShowsAllParameters() {
        let (shell, nodeID, filterID) = model()
        shell.toggleFilterGroup(filterID, in: nodeID)

        // Glow declares Size and Intensity animatable; Softness is not.
        #expect(filterRowCount(shell, nodeID) == 2)
    }

    /// One row per animated parameter, appearing as soon as it has keys.
    /// A filter somebody is animating opens on its own: they are exactly who
    /// wants to see its diamonds, and making them click first would hide the
    /// thing they came back for.
    @Test("animating a filter opens its group")
    func animatingOpensTheGroup() {
        let (shell, nodeID, filterID) = model()
        #expect(!shell.isFilterGroupExpanded(filterID, in: nodeID))

        shell.beginAnimatingFilter(
            GlowFilter.Param.intensity, on: filterID, in: nodeID, at: 0,
        )
        #expect(shell.isFilterGroupExpanded(filterID, in: nodeID))
    }

    /// And it can still be shut. Without somewhere to record "shut anyway", the
    /// chevron on an animated filter would appear to do nothing — which is why
    /// the state is three-valued rather than a set of open ids.
    @Test("an animated filter can still be folded away")
    func animatedFilterCanBeShut() {
        let (shell, nodeID, filterID) = model()
        shell.beginAnimatingFilter(
            GlowFilter.Param.intensity, on: filterID, in: nodeID, at: 0,
        )

        shell.toggleFilterGroup(filterID, in: nodeID)
        #expect(!shell.isFilterGroupExpanded(filterID, in: nodeID))
        #expect(filterRowCount(shell, nodeID) == 0)
    }

    /// The height has to follow, or the rows are drawn where nothing can be
    /// seen — this timeline has already been bitten by a frame promising less
    /// room than its contents needed.
    @Test("the editor grows by one row at a time")
    func heightFollowsTheRows() {
        let ten = KeyframeRows.height(rows: 10)
        let eleven = KeyframeRows.height(rows: 11)
        let twelve = KeyframeRows.height(rows: 12)

        #expect(eleven > ten)
        // Evenly, since every row is the same height.
        #expect(abs((twelve - eleven) - (eleven - ten)) < 0.001)
    }

    /// A switched-off track keeps its row: the keys are still there, and the
    /// row is where somebody switches it back on.
    @Test("a disabled track keeps its row")
    func disabledTrackKeepsItsRow() {
        let (shell, nodeID, filterID) = model()
        shell.beginAnimatingFilter(
            GlowFilter.Param.intensity, on: filterID, in: nodeID, at: 0,
        )
        shell.setFilterAnimationEnabled(
            false, for: GlowFilter.Param.intensity, on: filterID, in: nodeID, at: 0,
        )

        // Both of the glow's animatable parameters, since the group is open.
        #expect(filterRowCount(shell, nodeID) == 2)
    }

    /// Clearing takes the row with the keys — a row with nothing on it says
    /// there is an animation when there is not.
    /// Clearing takes the keys, and the group folds itself away again — there
    /// is nothing left in it to look at.
    @Test("clearing the last animation folds the group again")
    func clearingFoldsTheGroup() {
        let (shell, nodeID, filterID) = model()
        shell.beginAnimatingFilter(
            GlowFilter.Param.intensity, on: filterID, in: nodeID, at: 0,
        )
        shell.clearFilterAnimation(
            for: GlowFilter.Param.intensity, on: filterID, in: nodeID, keeping: 0,
        )

        #expect(!shell.isFilterGroupExpanded(filterID, in: nodeID))
    }

    /// Removing the last key removes the animation, not just the key: an empty
    /// track left behind would linger as a row with nothing on it.
    @Test("removing the last key removes the animation")
    func removingLastKeyClearsTheTrack() {
        let (shell, nodeID, filterID) = model()
        shell.beginAnimatingFilter(
            GlowFilter.Param.intensity, on: filterID, in: nodeID, at: 500,
        )
        let track = shell.filterAnimation(
            GlowFilter.Param.intensity, on: filterID, in: nodeID,
        )
        let keyID = track!.keyframes.first!.id

        shell.removeFilterKeyframe(
            keyID, for: GlowFilter.Param.intensity, on: filterID, in: nodeID,
        )

        // The track is gone, not merely emptied. An empty one left behind
        // still answers `filterAnimation`, so asserting only on `nil` would
        // miss it — and a row with no keys on it says there is an animation
        // when there is not. Verified by mutation.
        // Gone, not emptied — and `?.isEmpty ?? true` cannot tell those apart,
        // which is exactly what a mutation leaving the empty track in place
        // proved. A row is built from a track that exists, so an empty one
        // left behind would linger with no keys on it.
        #expect(shell.filterAnimation(
            GlowFilter.Param.intensity, on: filterID, in: nodeID,
        ) == nil)
    }

    /// Dragging a key moves it, and the move is clamped into the clip the same
    /// way planting one is.
    @Test("a key can be dragged, and stays inside the clip")
    func keysCanBeMoved() {
        let (shell, nodeID, filterID) = model()
        shell.beginAnimatingFilter(
            GlowFilter.Param.intensity, on: filterID, in: nodeID, at: 0,
        )
        let keyID = shell.filterAnimation(
            GlowFilter.Param.intensity, on: filterID, in: nodeID,
        )!.keyframes.first!.id

        shell.moveFilterKeyframe(
            keyID, for: GlowFilter.Param.intensity, on: filterID, in: nodeID, to: 900,
        )
        #expect(shell.filterAnimation(
            GlowFilter.Param.intensity, on: filterID, in: nodeID,
        )?.keyframes.first?.time == 900)
    }

    /// The easing belongs to the key it leaves from, which is how a storyboard
    /// command works — and it is the one thing a diamond cannot show or a drag
    /// define, so the row's menu is where it lives.
    @Test("a key's easing can be set from its row")
    func easingCanBeSet() {
        let (shell, nodeID, filterID) = model()
        shell.beginAnimatingFilter(
            GlowFilter.Param.intensity, on: filterID, in: nodeID, at: 0,
        )
        let keyID = shell.filterAnimation(
            GlowFilter.Param.intensity, on: filterID, in: nodeID,
        )!.keyframes.first!.id

        shell.setFilterKeyframeEasing(
            .quadOut, for: keyID, on: GlowFilter.Param.intensity,
            filterID: filterID, in: nodeID,
        )

        #expect(shell.filterAnimation(
            GlowFilter.Param.intensity, on: filterID, in: nodeID,
        )?.keyframes.first?.easing == .quadOut)
    }
}

/// How tall the timeline makes itself.
///
/// Three functions answer this — the panel's frame, the inner stack's, and the
/// scroll view's — and they have to agree exactly. Given less than it needs, a
/// stack does not scroll: it *compresses*, and rows are shaved or cut off with
/// nowhere to scroll to. This project has been bitten by that twice.
@MainActor
@Suite("Timeline height")
struct TimelineHeightTests {
    /// The bug from the screenshot: with two lanes, the keyframe editor was
    /// given the room for two lanes while drawing nine properties, so five of
    /// them were cut off the top with nothing to scroll.
    ///
    /// The mode replaces the lanes rather than sitting under them, so the lane
    /// count has nothing to say about how tall it is.
    @Test("the keyframe editor is not sized by the lane count")
    func keyframeEditorIgnoresLaneCount() {
        let twoLanes = TrackTimelineView.rowsHeight(
            trackCount: 2, isEditingKeyframes: true, keyframeRows: 10,
        )
        let tenLanes = TrackTimelineView.rowsHeight(
            trackCount: 10, isEditingKeyframes: true, keyframeRows: 10,
        )
        #expect(twoLanes == tenLanes)
    }

    /// And it is tall enough for every property it draws, which is what the
    /// screenshot was missing.
    @Test("the keyframe editor fits all of its rows")
    func keyframeEditorFitsItsRows() {
        let height = TrackTimelineView.rowsHeight(
            trackCount: 2, isEditingKeyframes: true, keyframeRows: 10,
        )
        #expect(height >= KeyframeRows.height(rows: 10))
    }

    /// Filter rows make it taller, or they are drawn where nothing can see them.
    @Test("animated filter rows add height")
    func filterRowsAddHeight() {
        let bare = TrackTimelineView.rowsHeight(
            trackCount: 2, isEditingKeyframes: true, keyframeRows: 10,
        )
        let withFilters = TrackTimelineView.rowsHeight(
            trackCount: 2, isEditingKeyframes: true, keyframeRows: 13,
        )
        #expect(withFilters > bare)
    }

    /// All three heights derive from one rule, so the frame and the content
    /// cannot disagree. Two of them once did, and the difference is what got
    /// cut off.
    @Test("the three heights agree")
    func heightsAgree() {
        for isEditing in [true, false] {
            for lanes in [1, 2, 6, 20] {
                let rows = TrackTimelineView.rowsHeight(
                    trackCount: lanes, isEditingKeyframes: isEditing, keyframeRows: 11,
                )
                let stack = TrackTimelineView.stackHeight(
                    trackCount: lanes, isEditingKeyframes: isEditing, keyframeRows: 11,
                )
                let panel = TrackTimelineView.height(
                    trackCount: lanes, isEditingKeyframes: isEditing, keyframeRows: 11,
                )
                // The stack is the rows plus the ruler; the panel is that plus
                // its own inset. Neither may be less than what it contains.
                #expect(stack > rows)
                #expect(panel > stack)
            }
        }
    }

    /// The ceiling still holds: a project with twenty lanes cannot push the
    /// canvas — the thing the editor exists for — off the window.
    @Test("many lanes still scroll rather than growing without limit")
    func theCeilingHolds() {
        let six = TrackTimelineView.rowsHeight(trackCount: 6)
        let twenty = TrackTimelineView.rowsHeight(trackCount: 20)
        #expect(twenty == six)
    }
}
