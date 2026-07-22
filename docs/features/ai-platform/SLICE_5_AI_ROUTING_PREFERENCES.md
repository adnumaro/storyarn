# Slice 5 — AI Routing + Personal Preferences (“My AI Team”)

## Objective

Provide one central route resolver and a personal “My AI Team” UI for choosing preferred providers/models by capability. Preferences help the current actor; they do not create shared project infrastructure and never authorize silent fallback.

## Personal preference model

Initial visible roles:

- Writing assistant
- Illustrator
- Voice

`Translator` is reserved in the role vocabulary but stays hidden and cannot be assigned until a registered, executable personal-BYOK translation task and translation execution adapter exist. Analyst remains a Storyarn AI system role in v1. A visible personal preference may point only to a healthy integration owned by that user and a compatible curated model. Unassigned roles may use the user's explicitly selected default personal AI only when it has the required capability; otherwise routing returns a repair/choose CTA.

“My AI Team” means personal defaults for explicitly initiated work. Project/workspace creative routing, shared credentials, and automated jobs are separate future concepts.

## Central route resolution

Consumers call `AI.resolve_route(ExecutionIntent)`; they never call `provider_for/2`, inspect integrations, or choose a fallback.

Resolution evaluates:

1. task lanes/capability and current workspace policy;
2. explicit lane/provider/model choice represented by a valid Slice-2 `requested_route_ref` for this invocation;
3. actor's compatible role/default preference when personal BYOK was requested;
4. Storyarn managed route when managed was requested;
5. provider/model health, consent, allowance, and operational switches.

Failure returns a classified CTA. It never changes payer or provider silently.

## Model capability catalog

- Capabilities are versioned per provider+model, not only per provider.
- Store structured output support, modality, context/output limits, region constraints, deprecation, and pricing-version metadata where known.
- Key validation/model discovery returns what the account can see; Storyarn intersects that list with its curated catalog.
- Listing a model does not prove endpoint access; runtime capability errors remain explicit.
- Removed/deprecated pinned models require repair; no silent substitution.
- DeepL metadata retains translation capability and has no model picker, but it is not a selectable “My AI Team” preference while no personal translation task can consume it.

## DeepL and localization decision

Do **not** drop `translation_provider_configs` in this slice. The legacy project configuration contains shared glossary ids, settings, hashes, and pending remote-deletion state that personal preferences cannot replace safely.

- Existing shared/project translation workflows keep their current configuration.
- Slice 5 does not create a personal DeepL execution adapter, task, or preference. Connecting a DeepL key remains useful connection metadata only until such a consumer ships.
- A future personal Translator preference may power only an explicitly user-initiated registered task that supports personal BYOK; adding that task is the gate that makes the role visible.
- Migration waits for a workspace-owned credential/routing design with an explicit batch actor and full glossary/settings migration plan.
- Localization settings must not link to a personal Translator preference until that executable consumer exists, and must never claim it is the project's canonical translator.

## Existing code to reuse

Slice-0 provider metadata/settings UI · Slice-2 TaskRegistry/route types · Slice-3 managed route · Slice-4 personal BYOK/consent/egress policy · existing select/combobox components · `Storyarn.Localization.BatchTranslator` boundaries · gettext/i18n.

## Non-goals

- Workspace/project-owned credentials.
- Shared project role assignments or per-language team routing.
- Personal translation/DeepL execution tasks or adapters.
- Destructive DeepL migration.
- Automatic fallback when a preference breaks.
- Dynamic multi-provider cost/quality optimization.

## Observability and error handling

- Audit preference create/update/delete and model deprecation repairs without secrets.
- Track assignment source in the resolved operation: explicit invocation, personal role, personal default, or platform managed.
- Provider disconnected, model unavailable, capability mismatch, and consent/policy denial remain distinct states.

## Verification / Definition of Done

- ExUnit: capability/model constraints, actor ownership, central route precedence, broken preference produces CTA, no silent payer/provider switch, Translator/DeepL cannot be assigned without a registered executable personal translation task, DeepL has no model path, legacy translation config remains untouched.
- Vitest/LiveView: visible role cards exclude Translator, DeepL is absent from assignable preferences, provider/model selector, unavailable/deprecated state, explicit defaults, Storyarn-vs-personal lane disclosure.
- Browser: configure two providers, assign different roles, revoke one, and verify affected commands show repair rather than fallback.
- User documentation explains personal preferences versus project/workspace policy.
- `just quality-lint` and full relevant suites green.

## Delivery

Branch `feat/ai-routing-preferences` from `main` → PR → merge before contextual AI tools. Keep `:ai_integrations` invite-only through browser verification of this slice.

## Inputs from previous slices

Slices 2–4 plus Slice-0 provider integrations.
