# Agent Constitution — Expense Tracking

This repo uses a strict Clean Architecture. Follow these laws on every change.

Product inventory (shipped vs deferred): [docs/STATUS.md](docs/STATUS.md).

## Module graph

```
CashFlowKit (Domain)  ←  CashFlowData (I/O)  ←  ExpenseTracking (UI)
```

| Module | May depend on | Must NOT use |
|--------|---------------|--------------|
| CashFlowKit | Foundation | SwiftUI, UIKit, SwiftData, URLSession, WidgetKit |
| CashFlowData | CashFlowKit | SwiftUI, UIKit, Feature ViewModels |
| ExpenseTracking | CashFlowKit, CashFlowData | SimpleFIN DTOs in Views; `ModelContext` in Views; ad-hoc networking |

## SOLID (everywhere)

Applies to **all** code: domain, data, features, design system, tests.

- **S** One type, one reason to change
- **O** Extend via new port implementations, not unrelated `switch` growth
- **L** Demo and SimpleFIN honor the same port contracts
- **I** Small ports in `CashFlowKit/Ports` — no god protocols
- **D** ViewModels/use cases depend on abstractions; only `DependencyContainer` constructs CashFlowData concretes

## Placement

- Money math / net / merge policy → `CashFlowKit`
- HTTP / SwiftData / Keychain / sync → `CashFlowData`
- Views + ViewModels → `ExpenseTracking/Features/<Feature>/`
- Wiring → `ExpenseTracking/App/DependencyContainer.swift` only

## Forbidden

- `Double`/`Float` for currency amounts
- Delete-transaction API
- Net cash flow math outside `CalculateNetCashFlowUseCase`
- Loading all transactions into the list UI (use keyset pagination)
- Constructing `SimpleFINBankLinkingService` outside `DependencyContainer`
- Parallel error mappers / raw `"CashFlowError error N"` UI — use `CashFlowError.userFacingMessage(for:fallback:)`

## Definition of done

1. Implement behind ports/use cases
2. Add/adjust tests that fail without the change
3. `swift test` in packages and/or `xcodebuild test` — green
4. `scripts/check_architecture.sh` — green
5. Demo happy path builds on Simulator

## Feature checklist

- [ ] New screen has a ViewModel
- [ ] Domain rules have unit tests in the same change
- [ ] No new singletons
- [ ] No `Double` money
- [ ] Filters/pagination stay at the repository layer
