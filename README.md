# Cash Flow

iPhone app that syncs accounts (**SimpleFIN** or **Demo**) and answers one question: **have I made more than I’ve spent?**

Display name: **Cash Flow** · Bundle ID: `com.expensetracking.app` · Platform: **iOS 17+** · Language: **Swift 6**

## Current status (MVP)

The end-to-end personal MVP is **built and runnable**:

| Area | Status |
|------|--------|
| Home — net, In/Out, ranges, cumulative chart, scrubbing | Shipped |
| Transactions — paginated list, filters, search, edit category/description | Shipped |
| Accounts — Demo + SimpleFIN link, sync, disconnect, reset, onboarding | Shipped |
| Widget — This Month net snapshot (small / medium / Lock Screen) | Shipped |
| Local SwiftData + Keychain; no backend | Shipped |
| Domain + data + app tests + architecture CI gate | Shipped |
| App lock — Face ID / Touch ID + passcode, 15s grace | Shipped |

**Not in MVP** (intentionally deferred): cloud backup / export, multi-device sync, CSV import, Plaid, delete-transaction, budgets, multi-currency, analytics.

See [docs/STATUS.md](docs/STATUS.md) for a fuller feature inventory and known limitations.

## Requirements

- Xcode 16+
- iOS 17+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Setup

```bash
xcodegen generate
open ExpenseTracking.xcodeproj
```

Run the **ExpenseTracking** scheme on an iPhone simulator (e.g. iPhone 17).

### Demo vs SimpleFIN

- **Demo:** Accounts → *Load Demo Data*, or onboarding → *Explore with Demo Data*. Token shortcut: `demo`.
- **Large list seed (10k+):** launch with argument `-largeDemoSeed`, then load demo (`demo-large` also works as a token).
- **SimpleFIN:** Accounts → *Link SimpleFIN…* → create a token at [SimpleFIN Bridge](https://bridge.simplefin.org/simplefin/create) → paste into the app.

Data is **device-local** (SwiftData + Keychain). Deleting the app removes local data. App Group `group.com.expensetracking.shared` feeds the widget (falls back to Application Support if the group isn’t available).

## Product rules (net cash flow)

| Kind | Contribution |
|------|----------------|
| Category **Income** | `+` |
| Other non-excluded categories | `−` |
| **Hidden**, **Transfer**, **Credit Card Payment** | excluded (`0`) |
| Pending transactions | ignored |

Ranges: **This Month** · **Last 30 Days** · **Last Year** · **Custom**.

Posted credit-card charges count as spent. User-edited **categories** are preserved across re-sync; amounts/dates/descriptions follow the remote merge policy.

## Architecture

Strict Clean Architecture. Start here:

- [AGENTS.md](AGENTS.md) — laws for humans and agents
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — modules, sync, UI map
- [docs/STATUS.md](docs/STATUS.md) — what’s shipped vs deferred
- [docs/TESTING.md](docs/TESTING.md)
- [docs/ADR/](docs/ADR/)

```
CashFlowKit (domain) ← CashFlowData (I/O) ← ExpenseTracking (UI)
                                         ← ExpenseTrackingWidget
```

Wiring lives only in `ExpenseTracking/App/DependencyContainer.swift`.

## Tests & CI

```bash
# Domain + data packages
(cd Packages/CashFlowKit && swift test)
(cd Packages/CashFlowData && swift test)

# Import / dependency gate
scripts/check_architecture.sh

# App tests (adjust simulator name if needed)
xcodebuild test -scheme ExpenseTracking -destination 'platform=iOS Simulator,name=iPhone 17'
```

GitHub Actions (`.github/workflows/ci.yml`) runs architecture checks, package tests, and `xcodebuild test` on `macos-15` for pushes/PRs to `main`.

## Privacy

No analytics. No app backend. Bank credentials are never stored by this app; SimpleFIN Access URLs live in the Keychain.
