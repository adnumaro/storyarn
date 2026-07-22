# Slice 4 — Personal BYOK Execution Lane

## Objective

Run registered AI tasks through the initiating user's own connected provider. Personal BYOK is an explicit, actor-owned lane: the provider bills that user, no Storyarn allowance is debited, and no other member or unattended/scheduled automation may use the credential.

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
- This slice adds `personal_byok` as an independently allowed lane, so a workspace may permit managed, personal BYOK, both, or neither.
- Existing operations retain the exact policy version used for their decision.

Only the workspace owner changes this policy through the existing `:manage_workspace` action in v1. Admins may inspect the effective state but cannot mutate it. Personal consent cannot override workspace prohibition. Provider allowlists, regional rules, and bulk budgets remain future enterprise extensions of the same policy contract.

## Consent and UX

- The lane is selected explicitly for an action or by an explicit personal preference added in Slice 5.
- First use is consented per workspace + integration/provider + capability/cost class + policy-text version.
- Copy states what project data scope will be sent and that the provider bills the user's account.
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

- Personal role/model preferences (Slice 5).
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

- ExUnit: sudo-protected credential mutation, atomic/durable audit, owner-only credential use, extension of the Slice-2 policy without a parallel resolver, independent managed/personal lane combinations, workspace egress denial, actor removal/revocation before an actor-initiated worker call, rejection of unattended/scheduled use, consent lifecycle, no allowance-ledger writes, capability-specific 403 does not revoke, invalid-key response does, task caps, no retries, sanitized telemetry.
- Vitest/LiveView: explicit lane choice, cost disclosure, consent modal, provider badge, connect/repair CTA, allowance-exhausted choice with no automatic switch.
- Browser: two users in one workspace prove that each can use only their own connection and cannot select the other's.
- User documentation covers who pays, what data is sent, and how to revoke consent.
- `just quality-lint` and full relevant suites green.

## Delivery

Branch `feat/ai-personal-byok-lane` from `main` → PR → merge before Slice 5. Keep `:ai_integrations` invite-only.

## Inputs from previous slices

Slice 0 integrations, Slice 2 kernel, and Slice 3 managed-lane/allowance states.
