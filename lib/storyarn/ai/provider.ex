defmodule Storyarn.AI.Provider do
  @moduledoc """
  Behaviour every AI provider adapter must implement.

  Adapters wrap the HTTP contract of a specific provider so `Storyarn.AI` can
  drive them uniformly. All providers in v1 authenticate with a user-supplied
  API key (BYOK); OAuth was ruled out during Slice 0 research — see
  `docs/features/ai-integrations/PROVIDERS.md`.
  """

  @typedoc "Provider identifier used in the database and URLs (e.g. `:anthropic`)."
  @type id :: atom()

  @typedoc """
  What a provider can be used for. Immutable per provider — owner-decided sets,
  declared in each adapter's `metadata/0` (provider context in
  `docs/features/ai-integrations/PROVIDERS.md`). Consumed by role assignments
  and lane resolution in later slices of the AI platform plan.
  """
  @type capability :: :translation | :suggestions | :tasks | :images

  @typedoc """
  Static metadata every adapter exposes for the UI and admin surfaces.

  * `:id` — machine identifier, matches `id/0`.
  * `:name` — human display name (never translated; provider brand).
  * `:key_generation_url` — where the user creates their key at the provider.
  * `:docs_url` — provider API documentation entry point.
  * `:key_placeholder` — hint shown in the connect input (safe to render).
  * `:capabilities` — immutable capability list (never user-configurable).
  """
  @type metadata :: %{
          id: id(),
          name: String.t(),
          key_generation_url: String.t(),
          docs_url: String.t(),
          key_placeholder: String.t(),
          capabilities: [capability()]
        }

  @typedoc """
  Result of a successful key validation.

  `:account_email` and `:account_display_name` are `nil` when the provider does
  not expose them via API — the UI falls back to the masked key.
  """
  @type account_info :: %{
          account_email: String.t() | nil,
          account_display_name: String.t() | nil
        }

  @typedoc "Reason returned when validation fails."
  @type validation_error ::
          :invalid_key
          | :network_error
          | :rate_limited
          | :provider_error
          | {:unexpected_status, integer()}

  @doc "Static metadata about the provider."
  @callback metadata() :: metadata()

  @doc """
  Validates that `api_key` is currently accepted by the provider and returns
  any account info the provider exposes.

  Implementations should perform a cheap, non-billing call (typically the
  models list endpoint). Timeouts and network failures are `:network_error`.
  """
  @callback validate_key(api_key :: String.t()) ::
              {:ok, account_info()} | {:error, validation_error()}
end
