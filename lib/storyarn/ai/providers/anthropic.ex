defmodule Storyarn.AI.Providers.Anthropic do
  @moduledoc """
  Anthropic Claude BYOK adapter.

  Uses `GET /v1/models` for cheap key validation. Anthropic does not expose an
  account-info endpoint accessible via API key, so `:account_email` and
  `:account_display_name` are always `nil` — the UI renders the masked key.

  See `docs/features/ai-integrations/PROVIDERS.md` for endpoint details.
  """
  @behaviour Storyarn.AI.Provider

  alias Storyarn.AI.Providers.KeyValidation

  @base_url "https://api.anthropic.com"
  @anthropic_version "2023-06-01"

  @impl true
  def metadata do
    %{
      id: :anthropic,
      name: "Anthropic Claude",
      key_generation_url: "https://platform.claude.com/settings/keys",
      docs_url: "https://docs.claude.com/en/api/getting-started",
      key_placeholder: "sk-ant-api03-...",
      capabilities: [:translation, :suggestions, :tasks]
    }
  end

  @impl true
  def validate_key(api_key) when is_binary(api_key) do
    __MODULE__
    |> KeyValidation.get(
      default_base_url: @base_url,
      url: "/v1/models",
      headers: [
        {"x-api-key", api_key},
        {"anthropic-version", @anthropic_version}
      ]
    )
    |> KeyValidation.classify()
  end
end
