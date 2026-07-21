defmodule Storyarn.AI.Providers.Mistral do
  @moduledoc """
  Mistral BYOK adapter.

  OpenAI-compatible API: bearer auth + `GET /v1/models` for validation.
  """
  @behaviour Storyarn.AI.Provider

  alias Storyarn.AI.Providers.KeyValidation

  @base_url "https://api.mistral.ai"

  @impl true
  def metadata do
    %{
      id: :mistral,
      name: "Mistral",
      key_generation_url: "https://console.mistral.ai/api-keys",
      docs_url: "https://docs.mistral.ai/getting-started/quickstart/",
      key_placeholder: "API key",
      capabilities: [:translation, :suggestions, :tasks]
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
