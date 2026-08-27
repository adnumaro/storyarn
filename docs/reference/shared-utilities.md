# Shared technical primitives

> Owner: Engineering
>
> Last reviewed: 2026-08-27
>
> Sources of truth: `lib/storyarn/platform/README.md`, the modules linked below,
> and `config/architecture_boundaries.exs`

This registry is intentionally small. Reuse a module only when the consumer
needs the same stable, business-neutral contract. When language, invariants or
ownership differ, keep a consumer-owned implementation even if that duplicates
code. `Storyarn.Platform` and `Storyarn.Shared` are not catch-all namespaces.

## Platform kernel

Kernel modules are deterministic and contain no persistence or provider I/O.

| Module | File | Contract |
| --- | --- | --- |
| `Storyarn.Platform.Kernel.MapAccess` | `lib/storyarn/platform/kernel/map_access.ex` | `stringify_keys/1` and atom/string-key lookup with `get_flexible/2` |
| `Storyarn.Platform.Kernel.IntegerParser` | `lib/storyarn/platform/kernel/integer_parser.ex` | Strict complete integer parsing with `parse/1`; integer-or-zero normalization with `ensure/1` |
| `Storyarn.Platform.Shared.StringUtils` | `lib/storyarn/platform/kernel/string_utils.ex` | Exact empty check with `blank?/1` and non-blank label fallback with `present_label/2` |
| `Storyarn.Platform.Shared.SearchHelpers` | `lib/storyarn/platform/kernel/search_helpers.ex` | Escapes `%`, `_` and `\\` before a value is interpolated into an `ILIKE` pattern |
| `Storyarn.Platform.Shared.HtmlUtils` | `lib/storyarn/platform/kernel/html_utils.ex` | Text extraction, truncation, word counts and documentation heading IDs; this is not an HTML sanitizer |

`IntegerParser.parse/1` rejects partial values such as `"42px"` and decimal
strings. Formula coercion is domain behavior and therefore stays in the owning
Sheet, Flow, Scene or Project implementation.

`StringUtils.blank?/1` deliberately does not trim. A consumer for which
whitespace is empty must keep that stronger rule locally.

## Platform technical adapters

| Module | File | Contract |
| --- | --- | --- |
| `Storyarn.Platform.Shared.TimeHelpers` | `lib/storyarn/platform/adapters/clock.ex` | `now/0`, UTC truncated to seconds; use it instead of direct `DateTime.utc_now/0` |
| `Storyarn.Platform.Shared.TokenGenerator` | `lib/storyarn/platform/adapters/security/token_generator.ex` | Generates and verifies hashed invitation/authentication tokens |
| `Storyarn.Platform.Shared.EncryptedBinary` | `lib/storyarn/platform/adapters/security/encrypted_binary.ex` | Cloak-backed encrypted Ecto type |
| `Storyarn.Platform.Shared.HtmlSanitizer` | `lib/storyarn/platform/adapters/security/html_sanitizer.ex` | Sanitizes untrusted HTML before `raw/1` or equivalent rendering |
| `Storyarn.Platform.Vault` | `lib/storyarn/platform/adapters/security/vault.ex` | Cloak vault used by encrypted persistence fields |

The historical `Storyarn.Platform.Shared.*` module identities above are stable
compatibility contracts. Their physical folders express the current ownership.

`HtmlUtils` strips markup for text processing; `HtmlSanitizer` enforces the XSS
allowlist. They are not interchangeable.

`Storyarn.Platform.Shared.HierarchySearch` is not a kernel primitive despite its
historical module name. It lives at
`lib/storyarn/platform/discovery/queries/hierarchy_search.ex` and is a read-only
Discovery coordinator used by global search. New business-context callers must
enter through the Platform discovery facade rather than importing it as a
generic helper.

## Presentation-only helpers

These modules belong to the Web adapter and must not be imported by domain
contexts:

| Module | File | Contract |
| --- | --- | --- |
| `StoryarnWeb.Helpers.Authorize` | `lib/storyarn_web/helpers/authorize.ex` | Reauthorizes mutating LiveView events through the owning context |
| `StoryarnWeb.Helpers.AutoSnapshot` | `lib/storyarn_web/helpers/auto_snapshot.ex` | Schedules and cancels debounced editor snapshot attempts; persistence gating stays in the owning facade |
| `StoryarnWeb.Helpers.ColorUtils` | `lib/storyarn_web/helpers/color_utils.ex` | Validates theme hex colors and converts them to CSS OKLCH values |
| `StoryarnWeb.Helpers.Severity` | `lib/storyarn_web/helpers/severity.ex` | Presentation ordering for the closed error/warning/info catalog |
| `StoryarnWeb.Helpers.SaveStatusTimer` | `lib/storyarn_web/helpers/save_status_timer.ex` | Marks a LiveView save as complete and schedules its status reset |
| `StoryarnWeb.Helpers.UndoRedoStack` | `lib/storyarn_web/helpers/undo_redo_stack.ex` | Generic bounded stack operations; each editor owns action interpretation and persistence |

Every mutating `handle_event` must use `with_authorization/3`,
`with_edit_authorization/2`, or an equivalent helper that calls
`authorize/2`. A cached `@can_edit` assign is presentation state, not an
authorization decision.

## Consumer-owned domain patterns

The following code is deliberately not shared:

- Project normalization and validation live in
  `lib/storyarn/projects/lifecycle/rules/name_normalizer.ex` and
  `lib/storyarn/projects/lifecycle/rules/validations.ex`. Other contexts own
  their slug, shortcut, variable and validation semantics.
- Shortcut allocation, tree operations, soft deletion, formulas, health
  severity and version summaries belong to their consumers. Copy an existing
  pattern only after confirming that its invariants match.
- Import persistence is split between the Flow, Sheet and Scene import writers
  under `lib/storyarn/projects/interchange/imports/commands/`; there is no
  generic import helper with cross-tool write authority.
- Project invitation schemas, operations and delivery live under
  `lib/storyarn/projects/access/`. Workspaces owns its separate invitation
  workflow and copy.

## AI canonical JSON

Canonical JSON is AI-owned because it participates in AI persistence and spend
guarantees. Each consumer keeps its own contract-local implementation:

| Owner | File |
| --- | --- |
| Context building | `lib/storyarn/ai/context_building/rules/canonical_json.ex` |
| Operations | `lib/storyarn/ai/operations/rules/canonical_json.ex` |
| Routing | `lib/storyarn/ai/routing/rules/canonical_json.ex` |

Do not recreate a Platform-wide canonical encoder. When adding an AI hash,
choose the copy owned by that exact contract and preserve its canonicalization
tests.

## Vue and LiveView utilities

- Reusable Vue components live under `assets/app/components/`; pure TypeScript
  helpers and composables live under `assets/app/shared/`.
- LiveView helpers live under `lib/storyarn_web/helpers/` or
  `lib/storyarn_web/live/shared/` and may coordinate presentation state only.
- Background jobs live under `lib/storyarn/workers/{owner}/` and enter business
  code through the owner's root facade.

Before adding a utility, search for the behavior, identify its owner, and check
`config/architecture_boundaries.exs`. Similar code is not sufficient evidence
that two consumers share one contract.
