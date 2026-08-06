import Foundation

/// Persists whether title cleanup stopped mid-backlog, so relaunching the app still offers
/// "Resume" instead of silently reverting to a fresh "Clean up transaction titles".
public protocol TitleCleanupStateStoring: Sendable {
    func isPaused() -> Bool
    func setPaused(_ paused: Bool)
}
