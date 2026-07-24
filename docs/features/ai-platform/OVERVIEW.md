# AI Platform — Overview & Slice Plan

Storyarn's AI strategy is **Storyarn AI by default, personal BYOK as the advanced lane, and future workspace BYOK for enterprise**. The durable advantage is Storyarn's structured narrative engine, not a generic chat or ownership of model weights.

> The engine knows what can be proved. Models explain, transform, and propose only within a typed, authorized task.

## Strategic pillars

1. **Storyarn AI is the frictionless product path.** Storyarn owns the provider relationship and presents concrete, bounded actions. During beta it is funded by a small internal workspace allowance; no payment system or public pricing is required.
2. **Personal BYOK remains first-class.** A user may explicitly run eligible tasks through their own connected provider. Only that user can spend the credential and the provider bills their account.
3. **Workspace BYOK is a future enterprise lane.** It will use organization/service credentials owned by the workspace, never a member's personal key shared with colleagues.
4. **Deterministic engine first, model second.** Graph queries, references, constraints, localization state, and validation produce the facts. Models narrate or propose where generation adds value.
5. **Tools, not open-ended chat.** Every action is a registered task with permissions, context scope, schemas, limits, lane policy, result destination, and provenance.
6. **Proposal before mutation.** Generated content is private preview data until the user explicitly applies or attaches it through existing facades with revision checks.
7. **Transparent payer and no silent fallback.** The UI always states `Storyarn AI` or `{Provider} · your key`. Changing lane, provider, or payer requires an explicit choice.
8. **One managed route first.** Interfaces remain provider-neutral, but multi-model optimization and self-hosting wait for measured quality, cost, and volume.

## Product layers

- **Command palette:** deterministic control surface and launcher. It never becomes a result store or grants the model arbitrary tool access.
- **Execution kernel:** intent, policy, route, operation, provider attempts, results, and outcomes.
- **Storyarn AI:** managed provider route, bounded allowance, fixed task prices, validation, and provenance.
- **Personal BYOK:** actor-owned credential route with owner-controlled member egress and external billing disclosure.
- **Tools:** structural analysis, dialogue, scratch VO, structure import, writing suggestions, and images.
- **Commercial billing:** deliberately last, after beta telemetry proves value and unit economics.

“My AI Team” exposes four personal roles: **General assistant** (`tasks`),
**Writing assistant** (`suggestions`), **Illustrator** (`images`), and **Voice**
(`speech`). General assistant covers explicit bounded work such as summaries,
analysis explanations, text-to-structure, and registered command-palette
actions; Writing assistant covers dialogue transformations and editor
suggestions. Illustrator and Voice may be configured in Slice 5.2, but their
media models remain `configuration_only` and cannot resolve an execution route
until Slice 12 and Slice 9 respectively ship and validate their dedicated
adapters.

## Slice index

| #   | Slice                                              | Document                           | Depends on                             | Status                               |
| --- | -------------------------------------------------- | ---------------------------------- | -------------------------------------- | ------------------------------------ |
| 0   | Personal provider connections + AI flag foundation | `SLICE_0_BYOK_INTEGRATIONS.md`     | —                                      | **merged** (PR #28)                  |
| 1   | Command palette foundation (no AI)                 | `SLICE_1_COMMAND_PALETTE.md`       | —                                      | **merged** (F1 PR #30; F2/F3 PR #31) |
| 2   | AI execution kernel + palette bridge               | `SLICE_2_AI_EXECUTION_KERNEL.md`   | 0, 1                                   | **merged** (PR #39)                  |
| 3   | Storyarn AI beta + internal allowance              | `SLICE_3_STORYARN_AI_BETA.md`      | 2                                      | **merged** (PR #42)                  |
| 4   | Personal BYOK execution lane                       | `SLICE_4_PERSONAL_BYOK_LANE.md`    | 0, 2, 3                                | **merged** (PR #43)                  |
| 5.1 | Central routing + workspace assignments            | `SLICE_5_1_ROUTING_ASSIGNMENTS.md` | 2–4                                    | **merged** (PR #44)                  |
| 5.2 | Personal AI preferences (“My AI Team”)             | `SLICE_5_2_MY_AI_TEAM.md`          | 5.1                                    | **merged** (PR #45)                  |
| 6   | Deterministic context engine v1                    | `SLICE_6_CONTEXT_ENGINE.md`        | 2                                      | implemented; PR in review            |
| 7   | Structural analysis + optional AI explanation      | `SLICE_7_STRUCTURAL_ANALYSIS.md`   | 1–6                                    | pending                              |
| 8   | Dialogue rewrite/variants + proposal UX            | `SLICE_8_DIALOGUE_TOOLS.md`        | 2–6                                    | pending                              |
| 9   | Multilingual scratch voice-over                    | `SLICE_9_SCRATCH_VOICEOVER.md`     | 0–5.2 + Localization/Assets            | pending                              |
| 10  | Text → Storyarn structure                          | `SLICE_10_TEXT_TO_STRUCTURE.md`    | 2–6, 8                                 | pending                              |
| 11  | Manual Tiptap writing suggestions                  | `SLICE_11_TIPTAP_SUGGESTIONS.md`   | 2, 4–6                                 | pending                              |
| 12  | Image generation into sheet galleries              | `SLICE_12_IMAGE_GENERATION.md`     | 2, 4–6                                 | pending                              |
| 13  | Commercial billing + paid allowances               | `SLICE_13_COMMERCIAL_BILLING.md`   | 3 + representative telemetry from 7–12 | deferred until data                  |

## Ordering rationale

- Slice 2 defines one execution/result/command contract before any provider or tool can invent a competing shape.
- Slice 3 makes Storyarn AI real with an internal beta allowance but deliberately excludes payments.
- Slice 4 integrates the already-shipped personal connections as an explicit lane.
- Slice 5.1 centralizes route resolution and workspace assignment before provider choice spreads into tools.
- Slice 5.2 adds one personal primary for each of four roles per actor+workspace,
  with no generic default, and separates advance media configuration from
  executable routes.
- Slice 6 creates bounded context without hidden model calls.
- Slice 7 proves the deterministic moat; Slice 8 proves proposal/apply and becomes the first tightly bounded writing transformation.
- Slice 9 ships a narrow, valuable VO preview using domain structures that already exist.
- Expensive/high-risk/broad tools follow only after the proposal, media, and execution contracts are proven.
- Slice 13 starts only after several weeks of representative usage; payments do not block beta.

## Workflow contract

1. One branch/PR per slice, cut from current `main`; merge hard dependencies before starting their consumer.
2. Re-verify all named modules/APIs against `main` at implementation start; these documents are contracts, not proof that code still has the same shape.
3. User-facing AI surfaces use the single product flag `:ai_integrations`, disabled by default and actor-targetable. Deterministic non-AI detectors may ship independently. Public documentation is not an entitlement boundary: invite-only AI beta relies on inline help, and Slice 7 publishes the AI guides for everyone when the first user-facing AI tool ships.
4. Task/provider operational switches and circuit breakers are allowed and required; they are not additional product entitlements.
5. Every user-facing slice ships en/es copy, user docs, browser verification, ExUnit/Vitest coverage, and the repository quality gate.
6. Reuse facades, authorization, mutation, storage, collaboration, versioning, and component registries. AI never creates a second write path.
7. No hour estimate is contractual. Size the slice after its implementation-start audit and split it if its acceptance criteria cannot fit one reviewable PR.

## Canonical execution contract

`ExecutionIntent → PolicyDecision → ExecutionRoute → Operation → UsageEvent(s) → Result/Proposal`

- Operation = one user intent and lifecycle.
- Usage event = one external provider attempt/cost record.
- Result = encrypted temporary output or typed proposal with TTL and source/version hashes.
- Apply = separate authorized domain mutation with reauthorization and stale checks.
- Short and background work share the same durable pipeline.
- No automatic inference retry in v1.
- `cancelled` is a pre-provider terminal state only. Once an external attempt starts, it settles to known success/failure or `unknown`; managed reservations commit/release exactly once.

Technical execution and human response are independent:

- `execution_status`: `queued | running | succeeded | failed | cancelled | unknown`
- `user_disposition`: `accepted | dismissed | abandoned | nil`

`viewed` is an event, never acceptance.

## TaskRegistry contract

Every task requires base `:use_ai` and declares phase-specific domain permissions, capability, data scope, allowed lanes, hard input/output limits, prompt/context/schema versions, execution mode, result destination/TTL, scheduled/bulk eligibility, managed price version, and operational enablement. Callers cannot override these values.

Provider/model capabilities are curated and versioned per model. Provider discovery is an intersection input, not proof that a model supports a modality or endpoint.

Catalog presence and role selection do not imply executability. A model entry's
`implementation_status` is either `executable` or `configuration_only`. A
configuration-only entry may be selected and persisted for advance setup, but
the resolver excludes it from route references, consent, and operations. Only
Slice 9 (`speech`) or Slice 12 (`images`) may promote the corresponding media
entry after its dedicated adapter, output-validation/storage boundary, and
contract tests pass. Catalog `implementation_status` is distinct from an
operation's queued/running/terminal `execution_status`.

## Lane and credential policy

### `managed`

- Storyarn owns the credential and provider cost.
- Workspace allowance is reserved before the call.
- User price is fixed/versioned; actual provider cost is internal telemetry.
- Technical/validation/unknown failure releases the reservation; a valid dismissed result remains charged.

### `personal_byok`

- Only the initiating credential owner may execute.
- No Storyarn allowance ledger mutation.
- Workspace owners may always choose their own personal route; other members require the owner-controlled personal-provider egress policy.
- Provider billing, consent, and accepted-result sharing are disclosed before execution.
- Personal credentials never power another member or unattended third-party automation.

### Future `workspace_byok`

- Workspace-owned service credential with admin policy, budgets, rotation, region/retention controls, and audit.
- Projects may reference an approved workspace route; they do not own duplicate secrets.
- Explicitly out of the current sliced roadmap until enterprise demand exists.

No lane silently falls back to another. If Storyarn AI allowance is exhausted,
no managed operation starts. The preflight may show an explicit **Use my own API
key** CTA only when the actor can use a compatible workspace-scoped BYOK role
preference. Choosing it opens the personal data/billing disclosure; a separate
BYOK operation may start only after current capability-scoped consent. Closing
or declining leaves the action blocked.

## Beta economics without payments

- Storyarn AI receives Storyarn-operator-configured promotional workspace grants.
- Internal units are called **AI allowance**, not wallet or purchased balance.
- Ledger is append-only and execution-safe, but no checkout/payment provider exists.
- Managed tasks have fixed beta prices/size bands; provider cost is stored separately.
- Global/workspace/user/task caps and provider-cost circuit breakers limit subsidy and abuse.
- Personal BYOK use is still metered for reliability/units but spends no Storyarn allowance.
- Commercial plans, subscriptions, top-ups, invoices, tax, refunds, and chargebacks belong to Slice 13.

## Data, permissions, and result ownership

- Minimum policy supports Storyarn AI allowed and personal BYOK allowed for members; workspace owners remain eligible to choose their own personal credential.
- Introduce explicit AI permissions rather than assuming all editors may spend future shared resources: `:use_ai`, `:run_bulk_ai`, and later routing/credential/budget administration.
- Reauthorize at operation creation, immediately before provider/credential access, and before apply/publish/attach.
- Unaccepted previews are actor-private. Accepted changes/assets become project data with provenance.
- Prompts, results, keys, and raw story text never enter analytics or normal logs.
- Temporary result/media retention and deletion are explicit per task.

## Command palette policy

- Palette remains unflagged; AI commands are registered only through Slice-2 descriptor v2.
- AI descriptors distinguish `launch` (open preflight/configuration, zero operations) from `execute` (complete server-validated intent, at most one operation). Explicit provider/model choices travel as short-lived server-issued route references, not trusted client fields.
- Natural-language intent may later map explicitly to allowlisted task ids, but raw palette queries are never sent automatically to a model.
- Availability is not authorization; every invocation revalidates server-side.
- Palette launches preflights or complete operations and routes to panels/editors. It does not own async lifecycle or hold result content.
- Cost/payer, CTA, pending state, idempotency, and result destination are declarative.

## Observability and product metrics

- Technical telemetry uses `[:ai, ...]`; product events use canonical space-separated names through `Storyarn.Analytics`.
- Record lane, task, provider/model, units, cost, latency, status, versions, and low-cardinality error class — no content/raw ids in analytics.
- Measure usefulness per task rather than one inflated global acceptance number:
  - rewrite/structure: proposal applied;
  - image/VO: asset attached;
  - structural analysis: evidence navigation, useful/false-positive, resolve/export;
  - suggestions: inserted.
- Track cost per accepted/useful result, managed-vs-BYOK choice, allowance exhaustion, and key-connection drop-off before pricing.

## Decisions locked by this rewrite

| Decision                 | Outcome                                                                                                                                              |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Beta payment system      | **Not required.** Internal allowance + metering only                                                                                                 |
| Managed user charge      | Fixed, versioned task price; real provider cost stays internal                                                                                       |
| Storyarn AI provider     | One active route; Fireworks primary, Together explicit alternative; verified ZDR + no-training, disclosed region, and no automatic provider fallback |
| Personal key sharing     | Forbidden; only credential owner may execute                                                                                                         |
| Automatic lane fallback  | Forbidden; exhaustion may offer an explicit BYOK preflight, but consent and a separate operation are required                                        |
| Media model readiness    | Image/speech entries are selectable `configuration_only` preferences until Slice 12/9 adapters make them executable                                  |
| DeepL migration          | Deferred; do not replace shared project config with personal preferences                                                                             |
| Hidden context summaries | Deferred from Context Engine v1; explicit user-launched summaries may use General assistant, but no hidden paid calls                                |
| Structural detectors     | Free deterministic product capability; AI explanation optional/gated                                                                                 |
| Scratch VO               | One target-locale line, personal BYOK, OpenAI initial target behind a provider-review gate, catalog voices, preview→Asset, `recorded` not `approved` |
| Commercial launch        | Subscription allowance first; top-ups only after separate evidence/approval                                                                          |

## Explicitly deferred

Workspace credential vaults · enterprise provider/model/region allowlists · department/member budgets · customer-managed KMS · self-hosted/open-weight operations · dynamic cheap/standard/premium routing · embeddings/semantic search · autonomous agents · voice cloning/custom voices · batch/table-read VO · automatic writing suggestions · paid top-ups/overages before demand · Storyarn MCP server.
