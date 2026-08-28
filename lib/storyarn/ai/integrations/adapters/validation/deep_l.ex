defmodule Storyarn.AI.Providers.DeepL do
  @moduledoc """
  DeepL BYOK adapter (translation-only).

  DeepL exposes no models endpoint; validation uses `GET /v2/usage` with
  `DeepL-Auth-Key` auth. API Free keys are suffixed `:fx` and live on a
  different host (`api-free.deepl.com`) than Pro keys (`api.deepl.com`) —
  each host rejects the other plan's keys, so the base URL is derived from
  the key shape.
  """
  @behaviour Storyarn.AI.Provider

  alias Storyarn.AI.Providers.KeyValidation

  @pro_base_url "https://api.deepl.com"
  @free_base_url "https://api-free.deepl.com"

  @impl true
  def metadata do
    %{
      id: :deepl,
      name: "DeepL",
      key_generation_url: "https://www.deepl.com/your-account/keys",
      docs_url: "https://developers.deepl.com/docs",
      key_placeholder: "API key",
      capabilities: [:translation]
    }
  end

  @impl true
  def validate_key(api_key) when is_binary(api_key) do
    __MODULE__
    |> KeyValidation.get(
      default_base_url: base_url_for(api_key),
      url: "/v2/usage",
      headers: [{"authorization", "DeepL-Auth-Key #{api_key}"}]
    )
    |> KeyValidation.classify()
  end

  defp base_url_for(api_key) do
    if String.ends_with?(api_key, ":fx"), do: @free_base_url, else: @pro_base_url
  end
end
