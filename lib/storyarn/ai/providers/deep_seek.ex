defmodule Storyarn.AI.Providers.DeepSeek do
  @moduledoc """
  DeepSeek BYOK adapter.

  OpenAI-compatible API: bearer auth + `GET /models` for validation. DeepSeek
  documents its base URL without a `/v1` prefix (both work; we follow their
  primary docs — see PROVIDERS.md).
  """
  @behaviour Storyarn.AI.Provider

  alias Storyarn.AI.Providers.KeyValidation

  @base_url "https://api.deepseek.com"

  @impl true
  def metadata do
    %{
      id: :deepseek,
      name: "DeepSeek",
      key_generation_url: "https://platform.deepseek.com/api_keys",
      docs_url: "https://api-docs.deepseek.com/",
      key_placeholder: "sk-..."
    }
  end

  @impl true
  def validate_key(api_key) when is_binary(api_key) do
    __MODULE__
    |> KeyValidation.get(
      default_base_url: @base_url,
      url: "/models",
      headers: [{"authorization", "Bearer #{api_key}"}]
    )
    |> KeyValidation.classify()
  end
end
