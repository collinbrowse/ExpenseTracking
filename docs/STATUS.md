# Product status

Snapshot of what this repo actually ships today. Keep this file honest when features land or slip.

## Shipped

### Home

- Hero **net cash flow** for the selected range, plus **In** / **Out**
- Range picker: Month · 30 Days · Year · Custom (date-picker sheet)
- Cumulative net **line chart** (axes first; line reveals left→right on first load)
- Press-and-drag scrubbing with callout; Reduce Motion respected
- Pull-to-refresh sync; offline / error banners
- Empty, loading, and populated states (no cross-fade stack on first load)

Code: `ExpenseTracking/Features/Home/`

### Transactions

- Bank-style list grouped by month (headers scroll with content)
- **Keyset pagination** (page size 50); loads more near the end of the list
- Filters (sheet): account, category, date (All / Month / 30d / Year / Custom)
- Search over **already loaded** rows: title, category, account, amount digits (e.g. `66` → `$66.43`)
- Edit sheet: category + description (no delete in MVP)
- Pull-to-refresh sync

Code: `ExpenseTracking/Features/Transactions/`

### Accounts & onboarding

- Connection status and last successful sync
- Load Demo / Link SimpleFIN (Bridge token → Access URL in Keychain)
- Sync Now; disconnect (keep data or wipe); reset local data
- Account list with balances
- First-launch onboarding: Demo · Link · Skip
- Settings (gear from Accounts): About + local-data privacy note

Code: `ExpenseTracking/Features/Accounts/`, `Features/Settings/`

### Sync & data

- `SyncCoordinator` — single-flight; failures keep last good local data
- Initial lookback ~2 years; later syncs use last-success watermark − 2 days
- Merge policy: user-edited **category** wins locally; remote wins amount / date / description
- Demo provider for fixtures / portfolio; SimpleFIN for real institutions
- Widget snapshot written after successful sync (`NetSnapshotStore`)

Code: `Packages/CashFlowData/`

### Widget

- Small, medium, and accessory rectangular layouts
- Shows **This Month** net + In/Out from the App Group JSON snapshot
- Uses `StaticConfiguration` (an `OpenCashFlowIntent` type exists but is not wired into the widget UI yet)

Code: `ExpenseTrackingWidget/`

### Quality gates

- Domain tests (`CashFlowKit`): net contribution, exclusions, ranges
- Data tests (`CashFlowData`): merge, demo net, sync-related coverage
- App tests (`ExpenseTrackingTests`): Home ViewModel, amount search helpers
- `scripts/check_architecture.sh` + GitHub Actions CI

## Known limitations (document accurately)

| Topic | Behavior today |
|-------|----------------|
| Transaction search | Client-side over **loaded pages only**, not a full-store query |
| Edited description | Saved locally, but **re-sync can overwrite description** from remote (category edits are protected) |
| Home date fetch | Posted txs for the range; date scoping may finish in memory when SwiftData predicates are fragile |
| App Group | Widget prefers `group.com.expensetracking.shared`; falls back if signing/team/group isn’t set up |
| Settings | About + privacy copy only — no preferences surface |
| Navigation helpers | `AppRouter` route enums exist but tabs use plain `NavigationStack`s |

## Deferred (not built)

- JSON / CSV export, cloud backup, multi-device sync
- CSV import, Plaid (or other aggregators requiring a backend)
- Delete transaction API (forbidden for MVP)
- Face ID / lock screen app lock
- Budgets, multi-currency, analytics, marketing screenshot pack

## Demo happy path (manual)

1. Launch app → onboarding → **Explore with Demo Data** (or Accounts → Load Demo Data)
2. Home shows positive/negative net for This Month and an animated chart
3. Transactions list scrolls; filters and search work on loaded rows
4. Edit a category → Sync Now → category should stick
5. Widget (after sync) reflects This Month snapshot when App Group is available
