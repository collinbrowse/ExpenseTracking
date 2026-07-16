# ADR 0003: Three-module boundary

## Status

Accepted

## Context

Need senior-level boundaries that AI agents and humans can enforce without a heavy micro-feature monorepo.

## Decision

Local SPM packages:

1. `CashFlowKit` — domain
2. `CashFlowData` — I/O adapters
3. `ExpenseTracking` app — UI + composition root

Plus CI script `scripts/check_architecture.sh` for forbidden imports.

## Consequences

- Illegal dependencies fail at compile time or CI
- Slightly more scaffold cost; much safer iteration
