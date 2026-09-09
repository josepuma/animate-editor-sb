import Foundation
import Testing

@testable import StoryboardCore

/// What version this build writes, and what it will still read.
///
/// The bump matters for one reason: a project written now names its scripts by
/// file, and one written before held their code inline. Without a version the
/// two are indistinguishable — and a file with no version cannot be told apart
/// from one written before versions existed, which is the whole argument for
/// having had `formatVersion` from the first release.
@Suite("Project version")
struct ProjectVersionTests {
    /// Scripts in files is a format change, so the version says so.
    @Test("this build writes version 2")
    func writesVersionTwo() {
        #expect(Project.currentVersion == 2)
    }

    /// A project from before the change still opens.
    ///
    /// It has to: the `.aesb` was the only place a script's code lived, and
    /// refusing to read it would strand exactly the work migration exists to
    /// rescue.
    @Test("version 1 is still readable")
    func versionOneStillOpens() throws {
        let old = try encoded(version: 1)

        let project = try ProjectFile.decode(old)

        #expect(project.formatVersion == 1, "the version it was written with, not ours")
        #expect(Project.minimumReadableVersion == 1)
    }

    /// A project from a newer build is refused rather than half-read.
    @Test("a newer version is refused")
    func newerVersionIsRefused() throws {
        let future = try encoded(version: Project.currentVersion + 1)

        #expect(throws: ProjectError.tooNew(Project.currentVersion + 1)) {
            try ProjectFile.decode(future)
        }
    }

    /// A saved project carries the current version.
    @Test("saving stamps the current version")
    func savingStampsCurrentVersion() throws {
        let data = try ProjectFile.encode(Project(document: EffectDocument()))

        let decoded = try ProjectFile.decode(data)

        #expect(decoded.formatVersion == Project.currentVersion)
    }

    // MARK: -

    /// A minimal project file at a given version.
    private func encoded(version: Int) throws -> Data {
        let json = """
        {"formatVersion": \(version), "document": {"tracks": []}}
        """
        return Data(json.utf8)
    }
}
