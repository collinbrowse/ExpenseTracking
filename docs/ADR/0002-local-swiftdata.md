# ADR 0002: Local-only SwiftData

## Status

Accepted

## Context

Personal MVP; no multi-device sync; delete-app may wipe data.

## Decision

SwiftData is the source of truth on device. Schema uses `VersionedSchema` v1 + `SchemaMigrationPlan`. The home-screen widget reads the shared App Group SwiftData store live (`WidgetNetCashFlowLoader`) for its configured time frame; leftover `NetSnapshotStore` JSON is cleared on full wipe.

`CashFlowSchemaV1` is the frozen live store shape: additive fields with defaults only. Breaking changes need a distinct V2 + migration stage. Wipe-on-load-failure in `ModelContainerFactory` is a last resort (it clears app + widget data together).

Local **CSV export** (`LocalDataExporting` / `LocalCSVExporter`) writes filtered transactions using the same `TransactionFilter` as the list UI. Cloud backup / multi-device sync remain out of scope.

## Consequences

- Fast iteration, strong privacy story
- Device-local JSON export for backup before risky resets or schema work
- Re-link / Sync Now / Reset remain first-class recovery paths
- Widget and app share one store — migrations and wipes affect both