# Slice 5.2 — Personal AI Preferences (“My AI Team”)

## Objective

Add personal provider/model preferences by role on top of the Slice-5.1 central resolver and workspace-assignment boundary. Preferences help the current actor choose an explicitly requested personal lane; they do not create shared project infrastructure and never authorize silent fallback.

## Personal preference model

Initial visible roles:

- Writing assistant
- Illustrator
- Voice

`Translator` is reserved in the role vocabulary but stays hidden and cannot be assigned until a registered, executable personal-BYOK translation task and translation execution adapter exist. Analyst remains a Storyarn AI system role in v1.

A preference is scoped to the actor and workspace. It may point only to:

- an active connection owned by that actor;
- a connection actively assigned to that workspace;
- a compatible, non-deprecated model from the Slice-5.1 curated catalog.

An unassigned role may use the actor's explicit default personal AI for that workspace only when it has the required capability. Otherwise routing returns a choose/repair CTA.

“My AI Team” means personal defaults for explicitly initiated work. Project/workspace creative routing, shared credentials, and automated jobs are separate future concepts.

## Resolver integration

Slice 5.2 extends the central resolver after the explicit route and authorization checks established by Slice 5.1:

1. resolve a compatible workspace-scoped role preference when the actor explicitly requests personal BYOK;
2. otherwise resolve the actor's compatible workspace-scoped personal default;
3. return a classified choose/repair CTA if neither is valid.

Preference resolution never falls back to Storyarn AI, another provider, another model, another member's connection, or a different payer.

Assignment source is captured as:

- `personal_role`;
- `personal_default`.

## Provider/model preference UX

- “My AI Team” shows one card for each visible role and a separate explicit personal default.
- Provider selection lists only healthy actor-owned connections assigned to the current workspace.
- Model selection intersects provider discovery with the curated catalog and required role capability.
- Disconnected, unassigned, unavailable, incompatible, and deprecated preferences remain visible as repair states; they are not silently rewritten.
- The UI always discloses `{Provider} · your key` and that the provider bills the actor's account.
- Workspace policy and assignment remain visible as separate concepts from a role preference.

## DeepL and localization decision

Do **not** drop `translation_provider_configs`.

- Existing shared/project translation workflows keep their current configuration, glossary ids, settings, hashes, and pending remote-deletion state.
- Slice 5.2 does not create a personal DeepL execution adapter, task, or preference.
- Connecting a DeepL key remains useful connection metadata only until an executable personal translation task ships.
- Localization settings do not link to a personal Translator preference and never claim it is the project's canonical translator.
- A future migration waits for a workspace-owned credential/routing design with an explicit batch actor and full glossary/settings migration plan.

## Existing code to reuse

Slice-5.1 central resolver, workspace assignments and model catalog · Slice-0 integration UI · Slice-2 task capability contracts · Slice-4 personal BYOK consent · existing select/combobox/card components · gettext/i18n.

## Non-goals

- Workspace/project-owned credentials.
- Shared project role assignments or per-language team routing.
- Personal translation/DeepL execution tasks or adapters.
- Destructive DeepL migration.
- Automatic provider/lane/payer fallback.
- Dynamic multi-provider cost/quality optimization.

## Observability and error handling

- Audit preference create/update/delete and model-deprecation repair without secrets.
- Provider disconnected, assignment missing, model unavailable/deprecated, capability mismatch, and policy/consent denial remain distinct states.
- Preference updates and resolver decisions include actor/workspace/role identifiers but no prompt, result, or credential content.

## Verification / Definition of Done

- ExUnit: role/default uniqueness, actor/workspace ownership, assignment and model-capability constraints, central preference precedence, broken preference CTAs, and no silent payer/provider switch.
- Vitest/LiveView: visible cards exclude Translator, DeepL is absent from assignable preferences, provider/model selectors, explicit default, unavailable/deprecated repairs, and Storyarn-vs-personal disclosure.
- Browser: configure two providers, assign them to eligible workspaces and different roles, revoke one, and verify affected commands show repair rather than fallback.
- User documentation explains personal preferences versus connection assignment, consent, and workspace policy.
- Frontend formatting, relevant backend/frontend suites, E2E coverage, and `mix precommit` are green.

## Delivery

Branch `codex/slice5-2-my-ai-team` from `main` after Slice 5.1 merges → PR → merge before contextual AI tools that consume personal defaults. Keep `:ai_integrations` invite-only through browser verification.

## Inputs from previous slices

Slice 5.1 plus Slices 0 and 2–4.
