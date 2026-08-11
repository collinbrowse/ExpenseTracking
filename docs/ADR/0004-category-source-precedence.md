# ADR 0004: CategorySource precedence

## Status

Accepted

## Context

Transaction categories are authored by keywords, on-device LLM enrichment, manual edits, and user rules. A sticky `userEditedCategory` bool alone cannot express that ranking or distinguish LLM from keyword.

## Decision

Persist `categorySource` (`keyword` < `llm` < `user` < `rule`) alongside a derived `userEditedCategory` compat flag (`isUserEditedCompat` for `.user` / `.rule` only).

Overwrite order on sync / re-apply (unchanged product behavior):

1. `categoryLocked` keeps the local category
2. Matching categorize **rule** wins (even over unlocked manual edits)
3. Else sticky **user** edit
4. Else **llm** / **keyword** processed sticky
5. Else **Undefined** until enrichment

`CategorySource.canOverwrite` uses the same ranks for enrichment and bulk assignment gates. Lock remains a separate flag, not a `CategorySource` case.

Legacy rows with `userEditedCategory == true` and `categorySource == nil` are treated as `.user` via `Transaction.effectiveCategorySource` and backfilled on merge. Writers stamp `categorySource` and derive the bool from it.

## Consequences

- Single authorship model for new writes without dropping the bool column yet
- Rule re-apply and merge stay aligned with AI-first Undefined ingest
- Schema stays on V1 additive fields; wiping the App Group store remains a last resort (see ADR 0002)
