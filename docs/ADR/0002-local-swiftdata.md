# ADR 0002: Local-only SwiftData

## Status

Accepted

## Context

Personal MVP; no multi-device sync; delete-app may wipe data.

## Decision

SwiftData is the source of truth on device. Schema uses `VersionedSchema` v1 + `SchemaMigrationPlan`. The home-screen widget reads the shared App Group SwiftData store live (`WidgetNetCashFlowLoader`) for its configured time frame; leftover `NetSnapshotStore` JSON is cleared on full wipe.

## Consequences

- Fast iteration, strong privacy story
- No cloud backup in MVP (export deferred)
- Re-link / Sync Now / Reset are first-class recovery paths
