defmodule Storyarn.AI.Providers.Moonshot do
  @moduledoc """
  Kimi (Moonshot AI) BYOK adapter.

  OpenAI-compatible API: bearer auth + `GET /v1/models` for validation. The
  global endpoint is `api.moonshot.ai`; the China-region `api.moonshot.cn`
  is not offered in v1 (revisit if users ask — see PROVIDERS.md).
  """
  @behaviour Storyarn.AI.Provider

  alias Storyarn.AI.Providers.KeyValidation

  @base_url "https://api.moonshot.ai"

  @impl true
  def metadata do
    %{
      id: :moonshot,
      name: "Kimi (Moonshot)",
      key_generation_url: "https://platform.moonshot.ai/console/api-keys",
      docs_url: "https://platform.moonshot.ai/docs",
      key_placeholder: "sk-..."
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
