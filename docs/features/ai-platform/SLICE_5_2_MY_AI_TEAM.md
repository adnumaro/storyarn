# Slice 5.2 — Personal AI Preferences (“My AI Team”)

## Objective

Add a clear account → workspace → role configuration flow on top of the Slice-5.1
central resolver:

- personal provider connections and encrypted keys belong to the actor's account;
- the actor explicitly assigns each connection to the workspaces where it may be
  used;
- “My AI Team” first summarizes every actor-visible workspace and then opens a
  dedicated editor for one workspace;
- that editor selects one primary provider/model for each visible role in the
  selected workspace.

The same account-level connection and key may serve several workspaces without
duplicating the secret. Each workspace may select different models for the same
role. These preferences configure only explicitly initiated personal BYOK work;
they do not create shared workspace credentials or allow another member to spend
the key.

## Product model

Connection, workspace assignment, and role preference are separate concepts:

1. **Connection:** an actor-owned account-level provider credential.
2. **Workspace assignment:** the actor's explicit permission to offer that
   connection in one workspace, subject to membership and workspace policy.
3. **Role primary:** the provider/model that the same actor prefers for one role
   in that workspace.

There is no generic global or workspace-wide personal default. A preference is
unique by `actor + workspace + role`. It may point only to:

- an active connection owned by that actor;
- that same connection actively assigned to the selected workspace;
- a compatible, non-deprecated model from the Slice-5.1 curated catalog and the
  provider's current discovery result.

For example, one OpenAI key may be assigned to a games workspace and a film
workspace while the Writing assistant role uses a different OpenAI model in
each. The key is stored once; only the workspace-scoped role preferences differ.

An unconfigured or invalid role returns a classified choose/repair CTA. It never
inherits a generic default and is never silently rewritten.

## Roles

Initial visible roles:

- **General assistant** (`tasks`): explicit summaries and bounded general
  actions launched from supported surfaces or the command palette.
- **Writing assistant** (`suggestions`): rewrites, variants, and manual writing
  suggestions.
- **Illustrator** (`images`): image-generation configuration for the Slice-12
  gallery workflow.
- **Voice** (`speech`): scratch voice-over configuration for the Slice-9
  localization workflow.

`Translator` is reserved in the role vocabulary but stays hidden and cannot be assigned until a registered, executable personal-BYOK translation task and translation execution adapter exist. Analyst remains a Storyarn AI system role in v1.

## Storyarn-owned model catalog

Personal model support is a versioned application contract, not deployment
configuration. Storyarn ships the provider/model allowlist in source control and
reviews it at least every two or three months, as well as when a provider
announces a retirement or breaking API change.

Every catalog entry has a model-level `implementation_status`:

- `executable`: Storyarn has reviewed the model contract and shipped the
  provider endpoint, request/response adapter, output validation, and result
  boundary required to execute it.
- `configuration_only`: the identifier and capability contract are reviewed,
  and the actor may select and persist it as an advance role preference, but no
  task may resolve it, request consent for it, or call the provider yet.

This catalog field is separate from an operation's lifecycle
`execution_status = queued | running | succeeded | failed | cancelled |
unknown`. A configuration-only preference is not a queued operation and must
never be presented as runnable.

A model enters the Storyarn-owned catalog only after its exact provider
identifier, capability, input/output modalities, structured-output mode,
release lifecycle, and `implementation_status` have been reviewed and committed
with tests. This admission decision is independent of any particular actor's
provider account.

A catalogued model is offered as a selectable option for one actor and role only
when all of the following are also true:

- the model declares every capability required by the selected role;
- the actor owns an active connection for that provider and has assigned it to
  the selected workspace; and
- the connected provider account currently exposes that model when discovery is
  available.

Provider discovery is therefore a narrowing signal, not the source of truth. A
provider may expose hundreds of models, but Storyarn offers only the reviewed
intersection. Conversely, a catalog entry does not promise that every account,
region, tier, or key can invoke it. Only `executable` entries are eligible for
route resolution and task consent.

The initial text catalog is:

| Provider  | Storyarn-supported model identifiers                                                | Capability                            | Modalities  | Structured output | Implementation status |
| --------- | ----------------------------------------------------------------------------------- | ------------------------------------- | ----------- | ----------------- | --------------------- |
| OpenAI    | `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna`                                      | `tasks`, `suggestions`, `translation` | text → text | `json_schema`     | `executable`          |
| Anthropic | `claude-fable-5`, `claude-opus-4-8`, `claude-sonnet-5`, `claude-haiku-4-5-20251001` | `tasks`, `suggestions`, `translation` | text → text | `json_schema`     | `executable`          |
| Google    | `gemini-3.6-flash`, `gemini-3.5-flash-lite`                                         | `tasks`, `suggestions`, `translation` | text → text | `json_schema`     | `executable`          |
| Moonshot  | `kimi-k3`, `kimi-k2.6`                                                              | `tasks`, `suggestions`, `translation` | text → text | `json_object`     | `executable`          |
| Mistral   | `mistral-large-2512`, `mistral-small-2603`                                          | `tasks`, `suggestions`, `translation` | text → text | `json_schema`     | `executable`          |
| DeepSeek  | `deepseek-v4-pro`, `deepseek-v4-flash`                                              | `tasks`, `suggestions`, `translation` | text → text | `json_object`     | `executable`          |

The initial reviewed media catalog is:

| Provider | Model identifier                                                                                            | Role capability | Input → output          | Structured output | Release stage | Implementation status | Activation |
| -------- | ----------------------------------------------------------------------------------------------------------- | --------------- | ----------------------- | ----------------- | ------------- | --------------------- | ---------- |
| OpenAI   | [`gpt-image-2`](https://developers.openai.com/api/docs/models/gpt-image-2)                                  | `images`        | text/image → image      | `none`            | `stable`      | `configuration_only`  | Slice 12   |
| OpenAI   | [`tts-1`](https://developers.openai.com/api/docs/models/tts-1)                                              | `speech`        | text → audio            | `none`            | `stable`      | `configuration_only`  | Slice 9    |
| OpenAI   | [`tts-1-hd`](https://developers.openai.com/api/docs/models/tts-1-hd)                                        | `speech`        | text → audio            | `none`            | `stable`      | `configuration_only`  | Slice 9    |
| Google   | [`gemini-3.1-flash-image`](https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-image)             | `images`        | text/image → text/image | `none`            | `stable`      | `configuration_only`  | Slice 12   |
| Google   | [`gemini-3.1-flash-lite-image`](https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-lite-image)   | `images`        | text/image → text/image | `none`            | `stable`      | `configuration_only`  | Slice 12   |
| Google   | [`gemini-3-pro-image`](https://ai.google.dev/gemini-api/docs/models/gemini-3-pro-image)                     | `images`        | text/image → text/image | `none`            | `stable`      | `configuration_only`  | Slice 12   |
| Google   | [`gemini-3.1-flash-tts-preview`](https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-tts-preview) | `speech`        | text → audio            | `none`            | `preview`     | `configuration_only`  | Slice 9    |

The catalog follows the providers' current [OpenAI image
generation](https://developers.openai.com/api/docs/guides/image-generation),
[OpenAI text-to-speech](https://developers.openai.com/api/docs/guides/text-to-speech),
[Gemini image generation](https://ai.google.dev/gemini-api/docs/image-generation),
and [Gemini speech
generation](https://ai.google.dev/gemini-api/docs/speech-generation)
contracts. Media does not use the existing structured-text Chat Completions
adapter: OpenAI images use `/v1/images/generations`, OpenAI `tts-1` and
`tts-1-hd` use `/v1/audio/speech`, and Gemini image and speech use the
Interactions API. Slice 5.2 only records advance configuration. Slice 9 or 12
may change a reviewed entry to `executable` only after its dedicated adapter,
media validation/storage boundary, consent flow, and contract tests ship.

Model identifiers, capabilities, structured-output mode, context limits,
deprecation state, `implementation_status`, and catalog version live in the
repository. Environment variables may hold feature switches, secrets, endpoint
overrides, and the operator-selected managed Storyarn AI route; they do not
define the personal model catalog or a hidden personal default.

## Settings information architecture

The account settings sidebar exposes two independent entries:

- **AI integrations:** connect and administer personal provider accounts.
- **My AI Team:** inspect every accessible workspace and choose
  workspace-scoped role primaries.

Do not hide “My AI Team” behind a tab inside AI integrations. The distinction
must remain understandable without knowing the storage model.

### AI integrations catalog

The catalog is a selection and status surface, not the place for full
configuration.

- Separate connected providers from available providers.
- Connected rows use the available width and show provider, masked key identity,
  health, assigned-workspace count, compatible-model count, and a concise repair
  warning when needed.
- Available providers may use a compact grid.
- Selecting a provider opens its dedicated detail screen.
- Do not show a generic “model status” or “connection only” section. Models
  become meaningful when a role is configured in “My AI Team”.

### Provider detail

The detail screen owns all configuration for one actor-owned connection:

- connection state, masked key identity, documentation, revalidation, key
  replacement, and disconnect;
- discovered/compatible models and provider-level warnings;
- workspace assignment management with enabled-first sorting, search/filter,
  counts, and bounded or paginated rendering suitable for many workspaces.

Do not render an unbounded workspace card stack in the provider catalog. The
catalog may show a count and summary; the searchable provider detail is the
source of truth.

### My AI Team overview

The default “My AI Team” page is read-only. It lists every workspace visible to
the actor and shows the selected provider/model for every visible role in one
scannable matrix. Each cell distinguishes:

- configured and healthy;
- configured but requiring repair;
- available but not configured;
- configured for a future tool (`configuration_only`); and
- no reviewed configurable catalog entry currently available for that role.

The overview never exposes another member's preferences, provider connection
identifier, credential metadata, or key. A workspace reached only through a
project remains informational and cannot be configured without a current
workspace membership. Workspaces blocked by owner policy stay visible with an
explicit explanation.

### Workspace team editor

Selecting **Configure** opens the existing editor at the route for that one
workspace. Keeping mutation on a dedicated workspace page reduces accidental
cross-workspace changes while the overview remains useful for comparison. The
editor has one configuration surface per visible role. Each role shows:

- capability and purpose;
- selected provider connection;
- primary compatible model;
- payer disclosure (`{Provider} · your key`);
- healthy, unconfigured, or specific repair state.

Only active actor-owned connections assigned to the selected workspace are
selectable. Model options intersect provider discovery with the repository
catalog and the role's required capability. A `configuration_only` model may be
selected and persisted, but the role surface must label it “configured for when
this tool becomes available” and cannot offer Run, consent, or execution
controls.

The workspace is fixed by the overview row and editor URL. Do not render a
workspace selector inside the editor: changing workspace returns to the
all-workspace overview and opens another workspace's dedicated route. A back
link always returns to that overview. A “copy configuration from another
workspace” action may reduce repetitive setup in a later slice, but every copied
preference must be validated and persisted independently for the destination
workspace.

## Resolver integration

Slice 5.2 extends the central resolver after the explicit route and authorization checks established by Slice 5.1:

1. resolve a compatible workspace-scoped role preference when the actor
   explicitly requests personal BYOK and its catalog entry is `executable`;
2. return a classified choose/repair CTA when that role has no valid primary.

Preference resolution never falls back to Storyarn AI, another provider, another model, another member's connection, or a different payer.

Assignment source is captured as `personal_role`. Route provenance also records
the actor, workspace, role, connection, provider, and primary model that were
revalidated for the invocation.

A saved `configuration_only` preference is intentionally absent from executable
route candidates. It remains visible as advance configuration; it does not
authorize consent or produce a route reference until the owning media slice
promotes that exact catalog entry to `executable`.

## Managed allowance exhaustion

The General assistant may support explicit summaries and other registered
`tasks` launched from the command palette or a bounded product surface. Its
presence in “My AI Team” never causes an automatic model call.

When a user explicitly chooses Storyarn AI and the workspace allowance is
exhausted:

1. the managed attempt is not created and the UI shows the classified
   allowance-exhausted state;
2. if an executable General-assistant personal route can be configured, the UI
   may offer an explicit **Use my own API key** CTA;
3. that CTA opens or completes the personal-BYOK preflight, discloses provider,
   model, data scope, and external billing, and requires capability-scoped
   consent before a new operation can be created;
4. a missing connection, workspace assignment, executable primary, policy
   permission, or consent produces a configuration/consent CTA instead of an
   operation.

Allowance exhaustion never switches lane, provider, model, payer, or credential
silently. A previously granted consent is not permission to perform automatic
fallback.

## Primary models and future alternatives

Slice 5.2 persists and resolves one explicit **primary** model per
`actor + workspace + role`. Consumers must use the central preference API rather
than assuming that a role is permanently represented by one model column; this
keeps the contract extensible to ordered alternatives.

Ordered alternatives and an explicit “retry with…” action may be added without
introducing a global default or another credential-ownership model. Automatic
fallback is out of scope:

- exhausting provider-account credit normally affects every model behind that
  key and is not solved by silently changing models;
- rate limits and model outages may justify an alternative, but the actor must
  explicitly select or retry it;
- ambiguous provider outcomes are never retried against another model;
- changing provider, model, lane, payer, quality, price, or data terms is never
  implicit.

## Credential rotation and repair

Key replacement is a safe rotation, not disconnect-then-connect:

1. validate the candidate key and discover its available models before changing
   the stored credential;
2. keep the existing encrypted key active if validation fails;
3. replace the key atomically after successful validation;
4. re-evaluate every affected workspace role preference against the refreshed
   model set;
5. preserve invalid preferences as explicit repair states and show the impacted
   workspaces/roles instead of silently deleting or substituting them.

Disconnect remains an explicit destructive action. It invalidates new route
resolution for every assignment and leaves affected role primaries visible as
repairable configuration. Secrets and validation payloads never appear in
catalog rows, URLs, audit metadata, analytics, or logs.

Repair states distinguish at least:

- provider disconnected;
- credential invalid or revalidation required;
- workspace assignment missing or policy-blocked;
- model unavailable or deprecated;
- model incompatible with the role capability;
- consent missing or revoked.

## DeepL and localization decision

Do **not** drop `translation_provider_configs`.

- Existing shared/project translation workflows keep their current configuration, glossary ids, settings, hashes, and pending remote-deletion state.
- Slice 5.2 does not create a personal DeepL execution adapter, task, or preference.
- DeepL is not offered as a new account-level personal AI connection until an
  executable personal translation task ships. A legacy connected row may remain
  visible only so its owner can disconnect it.
- Localization settings do not link to a personal Translator preference and never claim it is the project's canonical translator.
- A future migration waits for a workspace-owned credential/routing design with an explicit batch actor and full glossary/settings migration plan.

## Existing code to reuse

Slice-5.1 central resolver, workspace assignments and model catalog · Slice-0 integration UI · Slice-2 task capability contracts · Slice-4 personal BYOK consent · existing select/combobox/card components · gettext/i18n.

## Non-goals

- Workspace/project-owned credentials.
- Shared project role assignments or per-language team routing.
- A generic personal default outside `actor + workspace + role`.
- Personal translation/DeepL execution tasks or adapters.
- Destructive DeepL migration.
- Automatic model/provider/lane/payer fallback or retry.
- Dynamic multi-provider cost/quality optimization.

## Observability and error handling

- Audit role-primary create/update/delete, candidate-key validation outcome,
  successful key rotation, disconnect, and repair-state transitions without
  secrets. If workspace copy ships, audit it as an explicit batch of validated
  role-primary changes.
- Provider disconnected, credential invalid, assignment missing, model
  unavailable/deprecated, capability mismatch, and policy/consent denial remain
  distinct states.
- Preference updates and resolver decisions include actor/workspace/role identifiers but no prompt, result, or credential content.

## Verification / Definition of Done

- ExUnit: role-primary uniqueness by actor/workspace/role; actor ownership and
  cross-workspace isolation; one connection reused with different per-workspace
  models; repository-catalog defaults without model environment variables;
  all four visible role/capability mappings; assignment and capability
  constraints; `configuration_only` preferences persist but never resolve or
  authorize consent; no generic-default resolution;
  failed candidate-key validation preserving the previous key; successful
  rotation producing repair states for lost models; and no silent
  model/provider/payer switch.
- Vitest/LiveView: separate sidebar destinations; connected/available catalog
  sections; provider-detail navigation; searchable long workspace lists;
  all-workspace team overview; project-only access that is visible but cannot be
  configured; dedicated workspace editors without an internal workspace
  selector; four visible role surfaces excluding Translator; advance media
  configuration copy and disabled execution/consent affordances; DeepL absent
  from new personal connections and assignable preferences; provider/model
  selectors; unavailable/deprecated/assignment repairs; and payer disclosure.
- Browser: connect one provider, open its detail, assign the same connection to
  two eligible workspaces, choose different primary models for one role, rotate
  to a valid key with reduced model access, and verify the affected role shows a
  repair CTA rather than fallback. Also verify an invalid replacement leaves
  the existing connection usable.
- User documentation explains personal preferences versus connection assignment, consent, and workspace policy.
- Frontend formatting, relevant backend/frontend suites, E2E coverage, and `mix precommit` are green.

## Delivery

Branch `codex/slice5-2-my-ai-team` from `main` after Slice 5.1 merges → PR → merge before contextual AI tools that consume personal role primaries. Keep `:ai_integrations` invite-only through browser verification.

## Inputs from previous slices

Slice 5.1 plus Slices 0 and 2–4.
