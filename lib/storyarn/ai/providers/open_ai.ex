defmodule Storyarn.AI.Providers.OpenAI do
  @moduledoc """
  OpenAI BYOK adapter.

  Uses `GET /v1/models` with bearer auth for cheap key validation. Project API
  keys (`sk-proj-...`) cannot query account identity, so `:account_email` and
  `:account_display_name` are always `nil` — the UI renders the masked key.

  See `docs/features/ai-integrations/PROVIDERS.md` for endpoint details.
  """
  @behaviour Storyarn.AI.Provider

  alias Storyarn.AI.Providers.KeyValidation

  @base_url "https://api.openai.com"

  @impl true
  def metadata do
    %{
      id: :openai,
      name: "OpenAI",
      key_generation_url: "https://platform.openai.com/api-keys",
      docs_url: "https://platform.openai.com/docs/api-reference/authentication",
      key_placeholder: "sk-proj-...",
      capabilities: [:translation, :suggestions, :tasks, :images]
    }
  end

  @impl true
  def validate_key(api_key) when is_binary(api_key) do
    __MODULE__
    |> KeyValidation.get(
      default_base_url: @base_url,
      url: "/v1/models",
      headers: [{"authorization", "Bearer #{api_key}"}]
    )
    |> KeyValidation.classify()
  end
end
