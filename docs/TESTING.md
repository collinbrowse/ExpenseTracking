# Testing

## Pyramid

| Layer | Location | Required for |
|-------|----------|--------------|
| Domain unit | `Packages/CashFlowKit/Tests` | Any net / category / date / merge rule change |
| Data unit/integration | `Packages/CashFlowData/Tests` | Sync, merge, demo net, pagination/filter mapping |
| App / ViewModel | `ExpenseTrackingTests` | UI state orchestration (e.g. Home load, amount search) |
| Architecture script | `scripts/check_architecture.sh` | Every PR / push (CI) |
| UI smoke | Simulator + accessibility IDs | Release candidates |

## Commands

```bash
(cd Packages/CashFlowKit && swift test)
(cd Packages/CashFlowData && swift test)
scripts/check_architecture.sh
xcodebuild test -scheme ExpenseTracking \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

CI (`.github/workflows/ci.yml`) runs the same gates on `macos-15`, picking an available iPhone simulator for `xcodebuild test`.

## Money rules that must stay covered

- Income → `+`
- Expense categories → `−`
- Hidden / Transfer / Credit Card Payment → `0`
- Pending ignored
- User-edited **category** preserved on re-sync

## Agent definition of done

1. Tests that would fail without the change
2. Package and/or `xcodebuild test` green
3. `scripts/check_architecture.sh` green
4. Demo happy path builds on Simulator (see [STATUS.md](STATUS.md))

## Perf fixture

Launch with `-largeDemoSeed`, load Demo, scroll Transactions. Human / Instruments signs off jank.
