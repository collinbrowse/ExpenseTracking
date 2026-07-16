# Architecture

This document must stay aligned with [AGENTS.md](../AGENTS.md). For shipped vs deferred features, see [STATUS.md](STATUS.md).

## Style

Clean Architecture (layered) + **MVVM** at the UI edge. Swift 6 strict concurrency. SOLID applies to **all** code — domain, data, features, design system, and tests.

## Modules

| Module | Path | Responsibility |
|--------|------|----------------|
| **CashFlowKit** | `Packages/CashFlowKit` | Domain models, use cases, ports. **Foundation only.** |
| **CashFlowData** | `Packages/CashFlowData` | SwiftData, URLSession / SimpleFIN, Keychain, Demo provider, SyncCoordinator, NetSnapshotStore. |
| **ExpenseTracking** | `ExpenseTracking/` | SwiftUI features, DesignSystem, composition root (`DependencyContainer`). |
| **ExpenseTrackingWidget** | `ExpenseTrackingWidget/` | WidgetKit extension; reads `NetSnapshotStore` JSON. |

Dependency direction:

```
CashFlowKit  ←  CashFlowData  ←  ExpenseTracking
                              ←  ExpenseTrackingWidget
```

Features call **ports / use cases**. Only `ExpenseTracking/App/DependencyContainer.swift` constructs CashFlowData concretes (repos, Demo + SimpleFIN behind `CompositeBankLinkingService`, sync, resetter, connectivity).

### CashFlowKit (domain)

- Models: `Transaction`, `Account`, `Category` / `SystemCategory`, `CashFlowDateRange`, filters, errors
- Ports: `TransactionRepository`, `BankLinkingServing`, `SyncServing`, …
- Use cases: `CalculateNetCashFlowUseCase`, `CashFlowContribution`, `MergeSyncPolicy`

Money amounts are `Decimal` end-to-end in domain/data/UI models. Charts may convert to `Double` at the plot edge only.

### CashFlowData (I/O)

- Persistence: SwiftData schema v1, repositories, entity mappers, local reset
- Networking: `HTTPClient` → `SimpleFINClient` → `SimpleFINBankLinkingService`
- Demo: `DemoBankLinkingService` (+ composite router for Demo vs linked Access URL)
- Sync: single-flight `SyncCoordinator` + `SyncMergeEngine`
- Widget feed: `NetSnapshotStore` (App Group, with Application Support fallback)

### ExpenseTracking (UI)

| Feature folder | Role |
|----------------|------|
| `Features/Home` | Net hero, ranges, chart |
| `Features/Transactions` | Paginated list, filters, search, edit |
| `Features/Accounts` | Link / Demo / sync / onboarding |
| `Features/Settings` | About + privacy note |
| `DesignSystem` | Shared theme / formatting helpers |
| `App` | Entry, tabs, `DependencyContainer` |

## Navigation

`RootTabView`: **Home | Transactions | Accounts**. Each tab owns a `NavigationStack`. Sheets for custom range, transaction filters/editor, SimpleFIN link, and onboarding. Settings is pushed from Accounts (not its own tab).

## Net cash flow rules

Implemented only in `CalculateNetCashFlowUseCase` / `CashFlowContribution`:

- Income category → `+abs(amount)`
- Other non-excluded categories → `−abs(amount)`
- Hidden / Transfer / Credit Card Payment → `0`
- Pending → ignored
- Daily points are **cumulative** net over the selected range (chart ends at hero net)

## Sync

1. Provider fetch (Demo or SimpleFIN) via `BankLinkingServing`
2. Merge into SwiftData (`MergeSyncPolicy`: local category edits win; remote amount/date/description win)
3. On success, write month net snapshot for the widget
4. On failure, keep last good local data and surface a banner

`SyncCoordinator` is single-flight (overlapping syncs coalesce / cancel appropriately).

## Transactions performance

- Keyset pagination (page size **50**)
- Filter predicates applied at the repository layer where possible
- Preformatted `TransactionRowModel` strings; tiny `List` rows
- Search filters the **in-memory loaded page set** (not a separate full-table query)

## Concurrency

- ViewModels are `@MainActor` / `@Observable`
- Repositories and sync are actors (or actor-isolated) as appropriate
- Domain models are `Sendable`

## Enforcement

`scripts/check_architecture.sh` (also CI) fails on illegal imports — e.g. Kit using SwiftUI/SwiftData, Features using `ModelContext` / SimpleFIN DTOs / ad-hoc `URLSession`, or Features constructing `SimpleFINBankLinkingService`.
