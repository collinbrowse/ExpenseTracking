# ADR 0001: SimpleFIN over Plaid

## Status

Accepted

## Context

MVP requires bank sync without a backend and without CSV import. Plaid (and similar aggregators) need a server-held secret for production.

## Decision

Use **SimpleFIN Bridge**: user-paid (~$1.50/mo), Access URL claimed client-side, stored in Keychain. Abstract behind `BankLinkingServing` with a Demo implementation for portfolio/CI.

## Consequences

- No developer Plaid bill; no backend for MVP
- Institution coverage depends on SimpleFIN Bridge
- Future Plaid support can be another port implementation + thin BFF without rewriting Features
