import Foundation

/// Atomic link / disconnect / erase / reset orchestration for bank connections.
/// Kept separate from `SyncServing` (ISP) — lifecycle is a different reason to change.
public protocol ConnectionLifecycleServing: Sendable {
    /// Wipe local account data, then claim/link and sync. Demo and SimpleFIN are mutually exclusive.
    func replaceAndLink(withSetupToken token: String) async throws -> LinkedConnection

    /// Unlink credentials. When `deleteLocalData` is true, wipe store first (retry-safe), then unlink.
    func disconnect(deleteLocalData: Bool) async throws -> LinkedConnection

    /// Best-effort unlink + full local wipe (orphan recovery when Not linked but rows remain).
    func eraseEverything() async throws

    /// Wipe accounts/transactions/watermark/snapshot; keep credentials so Sync can re-pull.
    func resetLocalDataKeepingLink() async throws -> LinkedConnection
}
