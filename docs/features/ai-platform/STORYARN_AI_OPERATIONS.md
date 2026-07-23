# Storyarn AI Beta — Operations and Cost Runbook

## Scope

This runbook operates the invite-only managed lane introduced in Slice 3. The allowance is promotional internal capacity owned by a workspace. It is not purchased value and does not create checkout, subscriptions, invoices, top-ups, tax, refunds, or a public pricing commitment.

The only production task in this slice is the content-free operator diagnostic. No user-facing generation tool is enabled merely to exercise the infrastructure.

## Activation gate

The managed route fails closed. `STORYARN_AI_MANAGED_ENABLED=true` is insufficient on its own. Before enabling it, the Storyarn operator must have evidence for all of the following:

1. Zero data retention is enabled for the account/endpoint and covers the selected model.
2. Provider terms and account settings prohibit using prompts or generations for model training.
3. The configured processing-location label is accurate enough for the user disclosure. Region is disclosed, not used as an activation gate during the free beta.
4. The model supports the structured-output contract used by the diagnostic.
5. Current provider prices have been copied into an immutable price snapshot.
6. Conservative per-operation and global/workspace cost ceilings have been approved.

Fireworks is the primary beta provider. Its Chat Completions API is OpenAI-compatible, supports JSON-schema structured output, and its current documentation states that open-model inference has zero data retention by default unless the customer explicitly opts into logging. Storyarn does not use the Responses API, whose storage behavior differs. See [Fireworks zero data retention](https://docs.fireworks.ai/guides/security_compliance/data_handling), [structured outputs](https://docs.fireworks.ai/structured-responses/structured-response-formatting), [Chat Completions API](https://docs.fireworks.ai/api-reference/post-chatcompletions), and [serverless pricing](https://docs.fireworks.ai/serverless/pricing).

Together remains an explicit second option, not an automatic fallback. Before selecting it, revalidate the account and endpoint against [Together privacy](https://www.together.ai/privacy), [structured outputs](https://docs.together.ai/docs/inference/chat/structured-outputs), and [inference pricing](https://docs.together.ai/docs/inference/pricing).

## Runtime configuration

Configure the variables below when the managed lane is enabled. Only the selected provider's key is required; endpoint overrides are optional:

| Variable                                   | Purpose                                                         |
| ------------------------------------------ | --------------------------------------------------------------- |
| `STORYARN_AI_MANAGED_ENABLED`              | Manual global circuit breaker                                   |
| `STORYARN_AI_MANAGED_PROVIDER`             | `fireworks` (primary) or `together`                             |
| `STORYARN_AI_MANAGED_ZDR_VERIFIED`         | Operator ZDR attestation; must be `true`                        |
| `STORYARN_AI_MANAGED_NO_TRAINING_VERIFIED` | Operator no-training attestation; must be `true`                |
| `STORYARN_AI_FIREWORKS_API_KEY`            | Required when Fireworks is active; never persisted              |
| `STORYARN_AI_TOGETHER_API_KEY`             | Required when Together is active; never persisted               |
| `STORYARN_AI_FIREWORKS_ENDPOINT`           | Optional Fireworks HTTPS override; official endpoint by default |
| `STORYARN_AI_TOGETHER_ENDPOINT`            | Optional Together HTTPS override; official endpoint by default  |
| `STORYARN_AI_MANAGED_REGION`               | Content-free processing-location label shown to users           |
| `STORYARN_AI_MANAGED_MODEL`                | Single operator-selected model                                  |
| `STORYARN_AI_PROVIDER_PRICE_VERSION`       | Version of the provider-cost snapshot                           |
| `STORYARN_AI_PROVIDER_PRICE_CURRENCY`      | Currency used by all configured provider-cost limits            |
| `STORYARN_AI_PROVIDER_INPUT_PER_MILLION`   | Decimal provider input-token rate                               |
| `STORYARN_AI_PROVIDER_OUTPUT_PER_MILLION`  | Decimal provider output-token rate                              |
| `STORYARN_AI_PROVIDER_MAX_OPERATION_COST`  | Conservative reservation for one diagnostic request             |
| `STORYARN_AI_PROVIDER_GLOBAL_DAILY_CAP`    | Global daily provider-cost ceiling                              |
| `STORYARN_AI_PROVIDER_GLOBAL_MONTHLY_CAP`  | Global monthly provider-cost ceiling                            |
| `STORYARN_AI_PROVIDER_WORKSPACE_DAILY_CAP` | Uniform per-workspace daily provider-cost ceiling in Slice 3    |
| `STORYARN_AI_DIAGNOSTIC_PRICE_ID`          | Internal fixed allowance-price identifier                       |
| `STORYARN_AI_DIAGNOSTIC_PRICE_VERSION`     | Internal fixed allowance-price version                          |
| `STORYARN_AI_DIAGNOSTIC_PRICE_UNITS`       | Integer allowance units reserved and committed on valid output  |

Changing a provider rate, model, endpoint, task price, or task contract requires a version change and deployment. Existing operations retain their route, task-price, and provider-price snapshots.

### Switching providers

Set `STORYARN_AI_MANAGED_PROVIDER` and the selected provider's key/model/prices, then deploy or restart. The selector affects only newly issued route options. There is deliberately no request-time Fireworks→Together or Together→Fireworks fallback.

Both adapters remain registered so a queued operation can execute against the provider captured in its durable route. Keep the previous provider's key configured until those operations drain. Removing it earlier is safe but causes them to fail before an external attempt and release their allowance reservation. Never point one provider's endpoint variable at the other provider.

## Workspace onboarding

1. Target the owner and any invited testers with the existing `:ai_integrations` feature flag.
2. Issue an idempotent promotional grant. Use a stable grant key for the invitation wave or periodic window:

   ```bash
   mix storyarn.ai.grant \
     --workspace-id WORKSPACE_ID \
     --actor-id OPERATOR_USER_ID \
     --units UNITS \
     --key STABLE_GRANT_KEY \
     --kind one_time \
     --expires-at 2026-08-31T23:59:59Z
   ```

3. Have the workspace owner review the provider/model/region disclosure and enable Storyarn AI in workspace general settings. Admins and members see the state but cannot change it.
4. Run the production diagnostic with an owner who has the feature flag:

   ```bash
   mix storyarn.ai.diagnose --workspace-id WORKSPACE_ID --actor-id OWNER_USER_ID
   ```

The diagnostic follows normal policy, permission, allowance, cost-cap, provider, validation, and result-retention paths. It must not be bypassed with direct provider calls.

## Accounting invariants

- `ai_allowance_accounts` is the locked execution-time projection.
- `ai_allowance_ledger_entries` is append-only and content-free.
- Grants are consumed in earliest-expiry order.
- Reserve removes exactly the versioned task price from available allowance.
- Valid structured output commits exactly the reservation, even if the user later dismisses it.
- Pre-attempt cancellation/deauthorization and known, validation, timeout, or unknown failures release the user reservation.
- A release restores only allocations whose grants have not expired. Storyarn absorbs provider cost after any external attempt.
- Provider cost is a separate `Decimal` projection and never changes the task's allowance price.
- Idempotent operation creation and idempotent grant keys prevent double spend and duplicate grants.

## Reconciliation and alerts

`Storyarn.Workers.ReconcileAIReservationsWorker` runs every five minutes on the bounded `ai` queue. It:

- expires available units from elapsed grants;
- finds managed reservations stale for 15 minutes by default;
- fails stale queued operations;
- converts interrupted post-attempt work to `unknown` without another provider call;
- releases allowance through the normal operation transition; and
- records a durable, content-free operator alert.

Open rows in `ai_operator_alerts` require operator review. Critical kinds are `unknown_operation`, `stale_reservation`, `duplicate_attempt`, and `allowance_anomaly`; `provider_cost_spike` records cap blocks or actual cost above the reserved estimate.

Never manually retry an operation whose external outcome is unknown. Reconcile the provider request ID and account usage first, then create a new user intent only when the original outcome is proven terminal.

## Incident response

1. Disable `STORYARN_AI_MANAGED_ENABLED` and deploy/restart to remove the route globally. Existing queued work will fail reauthorization or be reconciled; no personal-key fallback occurs.
2. For one workspace, pause its allowance account or have the owner disable managed policy.
3. Inspect content-free operation, usage, budget reservation, allowance reservation, ledger, and alert rows by operation ID.
4. Compare provider request ID/token usage with the provider control plane. Never copy prompt or result content into logs, tickets, analytics, or alert metadata.
5. Rotate the managed key outside the database and restart the application. The credential reference in durable rows remains opaque.
6. Resolve alerts only after reservations and provider cost are reconciled. Ledger rows are never edited or deleted.

## Release verification

- Run the provider contract tests with `Req.Test`.
- Run allowance concurrency, expiry, cap, failure, unknown, and append-only tests.
- Verify owner/admin/member behavior in the existing authenticated `live_session :require_authenticated_user`; no new route or auth pipeline is introduced.
- Run one operator diagnostic only after ZDR, no-training, model, location-label, and pricing verification.
- Run `just quality-lint`, the relevant ExUnit/Vitest suites, and `mix test.e2e` before merge.
