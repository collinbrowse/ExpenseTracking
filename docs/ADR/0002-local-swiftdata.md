# ADR 0002: Local-only SwiftData

## Status

Accepted

## Context

Personal MVP; no multi-device sync; delete-app may wipe data.

## Decision

SwiftData is the source of truth on device. Schema uses `VersionedSchema` v1 + `SchemaMigrationPlan`. Widget snapshot written to App Group JSON (`NetSnapshotStore`) after sync, with Application Support fallback when the App Group container is unavailable.

## Consequences

- Fast iteration, strong privacy story
- No cloud backup in MVP (export deferred)
- Re-link / Sync Now / Reset are first-class recovery paths
