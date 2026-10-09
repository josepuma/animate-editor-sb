/// Chooses which project the home screen's hero plays.
///
/// Random, but never the one it played last time: with a handful of projects a
/// plain draw lands on the same map often enough to feel like it always does.
enum FeaturedPicker {
    static func pick<ID: Equatable>(
        from ids: [ID],
        avoiding last: ID?,
        using generator: inout some RandomNumberGenerator,
    ) -> ID? {
        let fresh = ids.filter { $0 != last }
        // One project is still worth showing, even if it showed last time.
        return (fresh.isEmpty ? ids : fresh).randomElement(using: &generator)
    }
}
