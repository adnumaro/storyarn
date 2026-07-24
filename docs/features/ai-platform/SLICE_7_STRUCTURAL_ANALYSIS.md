# Slice 7 — Split Decision

**Status:** superseded by Slice 7.1 and Slice 7.2 before implementation.

## Decision

The original Slice 7 combined two independently valuable products and too many
security/review boundaries for one PR:

| Slice | Product boundary                                                                  | AI gated? | Document                              |
| ----- | --------------------------------------------------------------------------------- | --------- | ------------------------------------- |
| 7.1   | Deterministic structural findings, lifecycle, and UI                              | No        | `SLICE_7_1_DETERMINISTIC_ANALYSIS.md` |
| 7.2   | Optional explanation of one selected finding through Storyarn AI or personal BYOK | Yes       | `SLICE_7_2_AI_EXPLANATION.md`         |

Slice 7.1 must merge first. It establishes the canonical finding id, rule
version, typed evidence, evidence fingerprint, permissions, and disposition
lifecycle consumed by Slice 7.2. Slice 7.2 must not invent a parallel detector
or accept client-authored evidence.

## Why this is a contract split

- Existing flow health checks and dashboard aggregates do not yet share one
  canonical finding/evidence shape.
- Persisting and invalidating false-positive dismissals is a domain feature,
  independent of provider availability or AI.
- The first user-facing AI task adds a separate vertical path: preflight,
  allowance, BYOK consent, payer, background execution, private result,
  staleness, palette integration, and public documentation.
- Reviewing both paths together would make it difficult to prove that
  deterministic facts stay separate from generated narrative.

This file is retained as a decision record and compatibility pointer. It is not
an implementation slice and does not receive its own branch or PR.
