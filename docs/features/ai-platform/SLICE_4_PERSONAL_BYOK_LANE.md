# Slice 4 — Personal BYOK Execution Lane

## Objective

Run registered AI tasks through the initiating user's own connected provider. Personal BYOK is an explicit, actor-owned lane: the provider bills that user, no Storyarn allowance is debited, and no other member or unattended/scheduled automation may use the credential. A workspace owner may always make this choice in a workspace they own; the workspace policy controls whether other eligible members may do so.

## Ownership rules

- Only the credential owner can initiate a provider call with that credential.
- A workspace owner/admin cannot inspect, select, or reuse another member's personal key.
- Personal credentials cannot become persistent project infrastructure or power third-party, cron, scheduled, or otherwise unattended automation.
- An async job created by an explicit actor action is allowed only as continuation of that action. It preserves the initiating actor and reauthorizes membership, workspace egress policy, task permission, integration health, and consent immediately before the call.
- Removing the actor from the workspace or revoking the key cancels a queued operation before provider access. If the external attempt already started, it follows the Slice-2 known/unknown finalization rules, cannot deliver or apply a result after authorization loss, and may still be billed by the provider. Already accepted project data remains with provenance.
- Future `workspace_byok` is a distinct lane backed by a workspace service credential, not “share my personal key”.

## Workspace egress policy

Extend the versioned Slice-2 workspace policy; do not introduce another policy record or resolver:

- Slice 2 already represents `AI disabled` as no allowed lanes and `Storyarn AI allowed` as the `managed` lane.
- This slice adds `personal_byok` as an independently allowed lane for non-owner members. A workspace may permit managed Storyarn AI, member personal BYOK, both, or neither; the owner remains eligible to choose their own personal credential even when member access is disabled.
- Existing operations retain the exact policy version used for their decision.

Only the workspace owner changes this policy through the existing `:manage_workspace` action in v1. Admins may inspect the effective state but cannot mutate it. For non-owner members, personal consent cannot override workspace prohibition. Provider allowlists, regional rules, and bulk budgets remain future enterprise extensions of the same policy contract.

## Consent and UX

- The lane is selected explicitly for an action or by an explicit personal preference added in Slice 5.2.
- First use is consented per workspace + integration/provider + capability/cost class + policy-text version.
- Workspace settings state that the owner can always use their own personal connections and that the switch grants access only to other eligible members.
- Copy states what project data scope will be sent, that the provider bills the user's account, and that processing region, retention, and possible model-training use depend on that member's provider account. Storyarn does not claim zero retention or no training for personal credentials.
- Badge: `{Provider} · your key`; provider/model and lane remain visible in result provenance.
- Missing, revoked, incapable, or unconsented integration yields an explicit connect/repair/consent CTA.
- There is no silent managed↔personal fallback. Reaching the Storyarn allowance shows choices; the user decides.

## Execution contract

- Add structured-text inference adapters for supported Slice-0 providers behind the Slice-2 inference behaviour.
- Credential access happens only through `CredentialRef`/store resolution and the existing encrypted runtime.
- BYOK operations create normal operations and usage events but never reserve, commit, or release Storyarn allowance.
- Record provider-reported units and latency; monetary cost is optional/estimated and clearly identified because the external account owns billing.
- Reuse Slice-0 last-used/audit behavior.
- Auto-revoke only provider-classified invalid/revoked credentials. Capability/permission-specific 403s do not revoke a valid key.

## Limits

- TaskRegistry caps apply equally to BYOK to protect queues, project data, and the user's provider bill.
- Bulk tasks require a separate confirmation with item/unit estimate.
- No automatic retry.
- Hidden context-generation calls are forbidden; each paid external call must be represented by a usage event and disclosed by the task.

## Existing code to reuse

Slice-0 encrypted integrations, providers, runtime, key validation, audit, and settings page · Slice-2 operations/TaskRegistry/PolicyDecision/CredentialRef · `Storyarn.RateLimiter` · existing workspace authorization/settings patterns · ConfirmDialog/native-dialog conventions · gettext/i18n.

Before broad rollout, close Slice-0 credential-security debt: connect/disconnect requires sudo mode; credential mutation and its audit record are atomic or use a durable outbox; runtime telemetry follows the Slice-2 low-cardinality/no-raw-user-id policy.

## Non-goals

- Personal role/model preferences (Slice 5.2).
- Workspace-owned credentials or enterprise provider policies.
- Automatic fallback from Storyarn AI.
- DeepL project-config migration.
- Payment or Storyarn-allowance ledger behavior.

## Observability and error handling

- Product events use space-separated canonical names and finite properties.
- Usage stores lane/provider/model/units/latency/status but no prompt/result.
- Revocation, policy denial, consent denial, capability mismatch, quota/rate limit, and provider failure are distinct localized states.
- Disconnect/reconnect creates a new credential lifecycle and requires fresh consent.

## Verification / Definition of Done

The platform overview deliberately schedules the first end-user AI task for Slice 7. Therefore this infrastructure slice must not add a fake task shell solely to exercise action UI. It ships and verifies the reusable preflight/consent/route contract plus the real settings surfaces. The first consuming task must complete the deferred action-level acceptance below.

- ExUnit: sudo-protected credential mutation, atomic/durable audit, owner-only credential use, extension of the Slice-2 policy without a parallel resolver, independent managed/personal lane combinations, workspace egress denial, actor removal/revocation before an actor-initiated worker call, rejection of unattended/scheduled use, consent lifecycle, no allowance-ledger writes, capability-specific 403 does not revoke, invalid-key response does, task caps, no retries, sanitized telemetry.
- Vitest/LiveView in this slice: independent managed/member-personal workspace controls, owner-always-eligible semantics, personal-data egress, provider retention/training and external-billing disclosure, owner-only member-policy mutation, key-management CTA, and sudo-protected connection mutation whose successful password confirmation rotates only the current browser session and remains valid for the shared twenty-minute window even after navigating through non-sensitive pages.
- Contract tests in this slice: preflight exposes `connect_required`, `consent_required`, and `ready` without leaking another member's integration; only `ready` receives an opaque route reference.
- Deferred to the first consuming task: explicit lane picker, per-action cost/data disclosure, consent modal, `{Provider} · your key` badge, connect/repair CTA, allowance-exhausted choice with no automatic switch, and a two-user browser proof that neither can select the other's connection.
- User documentation covers who pays, what data is sent, and how to revoke consent.
- `mix precommit`, Vitest, and full relevant E2E suites green.

## Delivery

Branch `codex/slice4-personal-byok-lane` from `main` → PR → merge before Slice 5.1. Keep `:ai_integrations` invite-only.

## Inputs from previous slices

Slice 0 integrations, Slice 2 kernel, and Slice 3 managed-lane/allowance states.
