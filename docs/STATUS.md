# Product status

Snapshot of what this repo actually ships today. Keep this file honest when features land or slip.

## Shipped

### Home

- Hero **net cash flow** for the selected range, plus **In** / **Out**
- Range picker: Month · 30 Days · Year · Custom (date-picker sheet). **Year appears only when local history reaches back a full year** (banks often return less than the requested lookback)
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

- Connection status and last successful sync (durable via `ConnectionEntity`)
- Load Demo / Link SimpleFIN through `ConnectionLifecycleServing` (**mutually exclusive**; link always wipes local accounts first)
- Sync Now; disconnect (keep data or wipe); clear local data (keep link); **Erase everything**
- Orphan leftover-data recovery when Not linked but rows remain
- Account list with balance on the trailing edge; tap opens Transactions filtered to that account
- Local account rename (survives sync while the SimpleFIN account still matches); new accounts take the SimpleFIN name
- First-launch onboarding: Demo · Link · Skip
- Settings (gear from Accounts): About + local-data privacy note + app lock

**Semantics**
| Action | Credentials | Local accounts/txns |
|--------|-------------|---------------------|
| Link / Load Demo (`replaceAndLink`) | Switch to new provider | Wiped, then re-synced |
| Disconnect (keep data) | Cleared | Kept |
| Disconnect & delete | Cleared | Wiped |
| Clear local data (keep link) | Kept | Wiped (Sync Now re-pulls) |
| Erase everything | Cleared | Wiped |

Code: `ExpenseTracking/Features/Accounts/`, `Features/Settings/`

### App lock

- Optional **Require Face ID / Touch ID** toggle in Settings (off by default)
- Unlock with system biometrics and **device passcode fallback** (`deviceOwnerAuthentication`)
- Re-locks after a fixed **15s** grace when leaving the app; quick switches do not re-prompt
- Full-screen privacy cover while locked or backgrounded with lock enabled (app switcher)
- Enabling / disabling requires a successful authentication challenge
- Widget **unchanged** — This Month net still shows when lock is enabled

Code: `ExpenseTracking/Features/AppLock/`, `Features/Settings/`, `CashFlowData/SecureStorage/`

### Sync & data

- `SyncCoordinator` — single-flight; cancel waits for slot; failures keep last good local data
- `connectionStatus` assembles Keychain/Demo + `ConnectionEntity` (`needsReauth`, last sync)
- Initial / incomplete history: ~2-year lookback (chunked ≤90 days with ~5-day overlap for SimpleFIN) until `historyBackfillComplete`; later syncs use watermark − 30 days
- Pending transactions are requested (`pending=1`), persisted, shown in the list, and flip to posted on the same sync key when the bank posts them; Home net still excludes pending
- Accounts list shows per-account sync health (Sync OK vs Bridge `errlist` issue); connection-scoped and account-scoped errors attach to the matching rows
- Merge policy: **locked** category always kept; else matching **user rule** wins (even over manual edits); else user-edited category; else remote suggestion. Account name: user-edited wins. Remote wins amount / date / description / balance / institution
- Category suggestion: user rules first, then built-in keywords (`SuggestTransactionCategoryUseCase`); unmatched credits → Other (not Income)
- Demo provider for fixtures / portfolio; SimpleFIN for real institutions — **not coexisting in one store**
- Widget snapshot written after successful sync; cleared on full wipe (`NetSnapshotStore`)
- Launch: single `VersionedSchema`; store load failures wipe App Group/local stores and retry, then in-memory — **no `fatalError` on SwiftData migration**

Code: `Packages/CashFlowData/`

### Widget

- Small, medium, and accessory rectangular layouts
- Shows **This Month** net + In/Out from the App Group JSON snapshot
- Uses `StaticConfiguration` (an `OpenCashFlowIntent` type exists but is not wired into the widget UI yet)

Code: `ExpenseTrackingWidget/`

### Quality gates

- Domain tests (`CashFlowKit`): net contribution, exclusions, ranges
- Data tests (`CashFlowData`): merge, demo net, sync-related coverage
- App tests (`ExpenseTrackingTests`): Home ViewModel, App Lock ViewModel, amount search helpers
- `scripts/check_architecture.sh` + GitHub Actions CI

### Categorization

- User rules: multi-condition AND filters (title/description contains|equals, account, amount min/max) stored in SwiftData
- Optional **rename title** action on rules (preserves location); applied with category on sync/re-apply
- Apply on sync/ingest before built-in keyword suggester; create/edit/delete re-applies to all **unlocked** transactions (including prior manual edits)
- Per-transaction **Lock category** toggle blocks rule overwrites (category and rename)
- Built-in keyword/phrase fallback remains (`SuggestTransactionCategoryUseCase`); unmatched credits → Other (not Income)
- UI: Settings → Categorization Rules; Create Rule… from transaction editor

Code: `CashFlowKit` (rules + resolve), `CashFlowData` (persist + reapply + merge), `ExpenseTracking/Features/CategorizationRules/`

## Known limitations (document accurately)

| Topic | Behavior today |
|-------|----------------|
| Bank history depth | SimpleFIN/Bridge only returns what the institution exposes; lookback requests older windows but empty older ranges are common |
| Transaction search | Client-side over **loaded pages only**, not a full-store query |
| Edited description | Manual / rule titles stick when category is sticky (`userEditedCategory`) or locked; otherwise re-sync can overwrite from remote |
| Home date fetch | Posted txs for the range; date scoping may finish in memory when SwiftData predicates are fragile |
| App Group | Widget prefers `group.com.expensetracking.shared`; falls back if signing/team/group isn’t set up |
| Settings | About + privacy + Categorization Rules + app lock |
| Navigation helpers | `AppRouter` route enums exist but tabs use plain `NavigationStack`s |

## Deferred (not built)

- JSON / CSV export, cloud backup, multi-device sync
- CSV import, Plaid (or other aggregators requiring a backend)
- Delete transaction API (forbidden for MVP)
- Budgets, multi-currency, analytics, marketing screenshot pack

### Categorization roadmap (remaining)

**Phase 1 — User rules** — shipped (see Categorization above).

**Phase 2 — On-device ML (experiment later)**  
Explore on-device models (Create ML / Core ML) trained on the user’s corrections + rules, still fully on-device. Treat as a learning spike; keep rules + keyword fallback as the safety net. Do not block shipping on this.

## Demo happy path (manual)

1. Launch app → onboarding → **Explore with Demo Data** (or Accounts → Load Demo Data)
2. Home shows positive/negative net for This Month and an animated chart
3. Transactions list scrolls; filters and search work on loaded rows
4. Edit a category → Sync Now → category should stick (unless an unlocked matching rule applies)
5. Settings → Categorization Rules → add a rule → matching unlocked txs update
6. Widget (after sync) reflects This Month snapshot when App Group is available
