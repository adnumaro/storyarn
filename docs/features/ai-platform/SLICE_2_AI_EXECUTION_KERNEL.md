# Slice 2 — AI Execution Kernel + Palette Bridge

## Objective

Build the provider-neutral, payment-neutral execution contract used by every AI feature: typed tasks, actor-scoped policy decisions, durable operations, per-attempt usage records, temporary results, explicit outcomes, and the command-palette bridge. This slice does **not** call a production model, grant AI allowance, or expose a user-facing AI tool.

## Product decisions locked by this slice

- An AI feature requests a registered **task**; callers never choose a raw model, price, prompt, or credential.
- `ai_operations` represent user intent and lifecycle. `ai_usage_events` represent individual provider attempts. In v1 one operation may have zero or one external usage event; a deliberate retry or regenerate action creates a new operation and idempotency key.
- Technical execution and human disposition are separate:
  - `execution_status`: `queued | running | succeeded | failed | cancelled | unknown`
  - `user_disposition`: `accepted | dismissed | abandoned | nil`
- Every operation is durable, including short operations. A short call may be awaited inline, but it uses the same record, result storage, and state machine as an Oban job.
- There are no automatic inference retries in v1. A provider call with an unknown outcome is never repeated automatically.
- Preview content is private to the actor until explicitly shared or applied. Accepted content becomes normal project data.
- Product telemetry and logs never contain prompts, result content, API keys, or raw palette queries.
- A successful preview that expires without a user decision becomes `abandoned`; a failed/cancelled/unknown execution has no user disposition. Disposition never overwrites execution status.

## Canonical execution flow

`ExecutionIntent → PolicyDecision → ExecutionRoute → Operation → UsageEvent(s) → Result/Proposal`

### `ExecutionIntent`

Server-built input containing the actor scope, workspace, optional project/entity, task id, selected revision/hash, an optional server-issued `requested_route_ref`, and an idempotency key. A preflight may let the user explicitly choose lane/provider/model, but the client sends only that opaque route-option reference; the server resolves and revalidates it for the current actor/task. Client-supplied permissions, raw provider/model, price, workspace/project ownership, or content scope are never trusted.

### `TaskRegistry`

Each task definition declares:

- stable task id and capability;
- allowed data scope, mandatory base `:use_ai`, and phase-specific `required_domain_permissions` for execute/apply/attach;
- allowed lanes: `managed`, `personal_byok`, and future `workspace_byok`;
- input/output schema versions and prompt version;
- hard serialized-input and output limits;
- execution mode, timeout, result type/destination, and result TTL;
- whether personal BYOK, bulk execution, or scheduled execution is allowed;
- whether the result stays private or may become shared;
- managed price id/version when the managed lane is allowed;
- operational `enabled?` control.

The caller cannot override these fields.

### `PolicyDecision` and `ExecutionRoute`

Authorization is separate from routing. The policy layer verifies feature entitlement, workspace egress policy, actor permission, entity access, task availability, lane eligibility, and rate limits. The route records lane, provider/model, opaque `CredentialRef`, payer, assignment source, policy version, and consent basis.

The persisted operation stores the resolved decision so audits do not depend on reconstructing policy that may later change.

This slice owns the base, versioned workspace AI policy and permission vocabulary even though it does not call a production provider:

- The policy stores an allowlist of execution lanes. It defaults to no allowed lanes (`AI disabled`) and initially supports enabling `managed` (`Storyarn AI allowed`). Slice 4 extends the same policy with `personal_byok`; it does not introduce a parallel policy model.
- Only the existing owner-only `:manage_workspace` authorization path may change the policy in v1. Admins may read its effective state but cannot mutate it unless a later slice introduces a narrower explicit action. Every change is audited and increments the policy version captured by later operations.
- Add `:use_ai` to the existing authorization system for explicitly initiated single-item AI tasks. Initial project-role mapping is `owner/editor = allowed`, `viewer = denied`; workspace-scoped tasks use `owner/admin = allowed`, `member/viewer = denied`. Encode those mappings directly even where they currently resemble edit access, so they can diverge later without changing task contracts.
- Add `:run_bulk_ai` as an additional permission. In v1 it is owner-only at the relevant project/workspace scope and always requires `:use_ai` too; admin/editor/member/viewer are denied. It is checked only when the registered task also declares bulk execution.
- Authorization always evaluates `:use_ai` plus the task's domain permission for the current phase. Execute may require `:view` or `:edit_content`; apply/attach normally requires `:edit_content`. Workspace policy and both permission layers are checked at operation creation, before execution, and before apply/attach; a feature flag or visible command grants none of them.

### Operation state machine and managed settlement

`queued` and `running` are non-terminal. `succeeded`, `failed`, `cancelled`, and `unknown` are terminal execution states; `user_disposition` is independent and may be set only for a successful result.

| From | Proven event | To | Managed allowance |
|---|---|---|---|
| no operation | launch/preflight or policy block | no operation | no reservation |
| no operation | idempotent execute intent accepted | `queued` | reserve fixed task price exactly once |
| `queued` | explicit cancellation, lost authorization, or revoked route before the external call | `cancelled` | release reservation |
| `queued` | worker claims and reauthorization passes | `running` | keep reservation held |
| `queued`/`running` | confirmed local setup/validation failure before billable provider work | `failed` | release reservation |
| `running` | valid provider result and output validation | `succeeded` | commit fixed task price exactly once |
| `running` | confirmed provider/validation failure | `failed` | release reservation |
| `running` | provider outcome cannot be proven | `unknown` | release user reservation, record possible provider cost, reconcile without retry |

There is no `running → cancelled` transition once an external attempt begins. A cancellation, membership loss, policy change, or credential revocation during the call prevents delivery/apply and records a cancellation request, but the attempt finalizes as `succeeded`/`failed` if its outcome is known or `unknown` otherwise. BYOK has no Storyarn reservation, but the external provider may still bill any started attempt. Every managed reservation reaches exactly one durable commit or release.

### Durable result contract

- Structured results are encrypted at rest and actor-scoped.
- Default beta TTL: 24 hours, configurable by result type. Accepted project data follows normal project retention.
- An expiry worker deletes temporary content and finalizes only successful, undecided previews as `abandoned`.
- Polling is authoritative; PubSub only accelerates updates.
- Retention is split explicitly: encrypted prompt/result/media content follows its short task TTL, while content-free operation, usage, policy-decision, idempotency, and future allowance-ledger records follow a separate audit/financial retention policy.
- Deleting a project/workspace deletes temporary content and removes or pseudonymizes project/user references according to policy; it must not cascade away operation/usage/ledger history required for reconciliation or abuse investigation.
- Every result stores task, prompt, context-builder, and output-schema versions plus the exact input hash.

## Provider boundaries

- Keep Slice-0 connection metadata/key validation separate from inference execution.
- Introduce an inference behaviour for structured text generation without adding a managed provider to the connectable-provider card registry.
- Runtime consumers receive an opaque `CredentialRef`; they do not query `ai_integrations` directly.
- Speech and images will use modality-specific behaviours in their own slices rather than widening a text-only `generate/2` contract indefinitely.
- A deterministic fake provider is the only implementation required in this slice.

## AI command-palette contract v2

The existing synchronous palette descriptor remains valid for non-AI commands. No AI command may register until the additive v2 contract exists. AI descriptors are discriminated:

- `launch`: opens a task-specific configuration/preflight destination. It creates no operation, performs no provider call, and returns `launched | blocked | failed`. Use it whenever text, scope, direction, lane, provider/model/voice, or consent still requires user input.
- `execute`: has a complete server-resolved subject and route option and may create exactly one operation. It returns `succeeded | queued | blocked | failed`, with operation id and destination only for `succeeded/queued`.

Both forms declare a stable content-free command id, task id, current surface/selection, server-resolved availability, and declarative destination. `execute` includes resolved cost disclosure. `launch` declares `cost = deferred_to_preflight`; its destination must show the resolved payer/price and obtain explicit confirmation before calling `AI.execute/1`.

Preflight returns allowlisted route choices as opaque, short-lived `requested_route_ref` values bound to actor, workspace, task, subject revision, lane/provider/model, policy version, and price version. Confirmation sends the reference rather than authoritative raw routing fields; execution resolves and revalidates it atomically. An expired or mismatched reference returns a classified refresh state, never a fallback.

Normative rules:

- Availability is presentation, not authorization; invocation revalidates everything server-side.
- `hidden` is used for flag-off, wrong surface/context, or missing base permission. `cta` is shown only when the CTA itself is executable.
- Cost is resolved from the TaskRegistry and current lane, never from client constants. A launcher may defer disclosure only because it cannot execute; the destination shows cost before confirmation.
- One `launch` selection creates no operation. One `execute` selection creates at most one operation. Pending items are disabled and expose an accessible loading state.
- The palette closes after `launched`, `queued`, or `succeeded`; blocked/failed keeps it open with a localized error/CTA.
- Closing the palette never means the provider call was cancelled.
- Result destinations are declarative (`panel`, `inline_editor`, `route`, or `none`); descriptors never contain result content or raw URLs.
- `"palette command executed"` is emitted after a launcher successfully opens its destination or after the server accepts an idempotent execute operation — never on click, blocked state, or provider completion. AI operation telemetry remains canonical for later execution outcomes.
- AI command ids and analytics allowlists derive from one canonical catalog.

Before the first AI command, the palette foundation must also fix: server-search pending/no-results semantics, permission-aware settings commands, Promise rejection handling, flag propagation, and `Cmd/Ctrl+K` access from explicitly supported editable contexts.

## Authorization lifecycle

Authorization runs:

1. when the operation is created;
2. immediately before resolving a credential and calling a provider;
3. before applying, publishing, or attaching the result.

Revoked credentials, changed workspace policy, stale entity revisions, or lost membership prevent later stages from proceeding.

## Existing code to reuse

`Storyarn.AI` facade and Slice-0 integration runtime/audit patterns · `Storyarn.RateLimiter` · Oban and existing worker conventions · Cloak/encrypted-field patterns · `Storyarn.Analytics` allowlists · current scope/authorization facades · command-palette registry and LiveView hook · `Shared.TimeHelpers`.

## Non-goals

- Production provider calls.
- Storyarn AI allowance or allowance ledger.
- Payment integration, subscriptions, purchases, or pricing tiers.
- Workspace-owned credentials.
- Model routing or personal role preferences.
- User-facing generation tools.

## Observability and error handling

- Telemetry spans use `[:ai, ...]` and low-cardinality metadata.
- Usage records store counts, latency, provider request id when available, cost data, versions, and classified error only.
- Unknown external outcomes remain `unknown`, generate an operator alert, and are not retried.
- A duplicate external-attempt invariant violation is blocked before the call and generates an operator alert; v1 never appends a second provider attempt to the same operation.
- Operation failure and user dismissal are never collapsed into one field.
- No swallowed errors or silent fallbacks.

## Verification / Definition of Done

- ExUnit: task validation; mandatory `:use_ai` plus phase-specific domain permissions; base workspace-policy default/managed transitions, authorization, audit/version capture; exact project/workspace role matrices for `:use_ai` and owner-only additive `:run_bulk_ai`; actor/project authorization; route-reference binding/expiry/revalidation; idempotent operation creation; legal lifecycle transitions and settlement; zero-or-one external usage cardinality and duplicate-attempt rejection; encrypted content TTL; project/workspace deletion retains required content-free audit/usage/ledger records; reauthorization before execution/apply; unknown-outcome handling; no-content telemetry.
- Vitest: discriminated launch/execute runners, launch creates no operation, deferred-vs-resolved cost, pending state, classified blocked/failed state, result routing, flag/permission availability, rejected Promise does not close or record success.
- Palette regression tests: no false no-results while server search is pending; editable-context shortcut policy; inaccessible project settings are not offered.
- Real-provider-independent contract tests using the deterministic fake.
- `just quality-lint` and full relevant suites green.

## Delivery

Branch `feat/ai-execution-kernel` from `main` → PR → merge before Slice 3. The kernel has no user-facing AI surface; `:ai_integrations` remains disabled by default.

## Inputs from previous slices

Slice 0 integrations/feature flag and Slice 1 command palette foundation.
