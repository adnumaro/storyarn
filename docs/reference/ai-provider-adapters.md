# AI provider adapters

> Owner: Engineering
>
> Last reviewed: 2026-08-27
>
> Source of truth: `lib/storyarn/ai/integrations/contracts/provider.ex`,
> `lib/storyarn/ai/integrations/adapters/provider_registry.ex`, and
> `lib/storyarn/ai/integrations/adapters/validation/`

`Storyarn.AI.Provider` is the contract for personal-provider connection
adapters. The ordered registry drives provider discovery, identifiers, metadata,
and the settings UI.

## Adapter contract

Each adapter exposes static metadata and validates a user-supplied API key with
a cheap, non-billing request. Validation returns optional account/model metadata
or one of the closed errors defined by the behaviour. Network calls use the
shared key-validation module and support test/runtime endpoint overrides.

Capabilities are provider metadata, not proof that an end-user task exists.
Tasks and route resolution must separately validate model, capability,
assignment, consent, and authorization.

## Registered adapters

| Provider  | Capabilities                                    | Validation                                                   |
| --------- | ----------------------------------------------- | ------------------------------------------------------------ |
| Anthropic | translation, suggestions, tasks                 | `GET /v1/models` with `x-api-key` and `anthropic-version`    |
| OpenAI    | translation, suggestions, tasks, images, speech | `GET /v1/models` with bearer auth                            |
| Google    | translation, suggestions, tasks, images, speech | `GET /v1beta/models?pageSize=1000` with `x-goog-api-key`     |
| Moonshot  | translation, suggestions, tasks                 | `GET /v1/models` with bearer auth                            |
| Mistral   | translation, suggestions, tasks                 | `GET /v1/models` with bearer auth                            |
| DeepSeek  | translation, suggestions, tasks                 | `GET /models` with bearer auth                               |
| DeepL     | translation                                     | `GET /v2/usage`; the key suffix selects the Free or Pro host |

Provider terms, pricing, retention, geographic processing, key formats, and
public endpoints can change independently of this repository. Verify those
claims against primary provider documentation when changing an adapter; do not
copy time-sensitive research into this file.
