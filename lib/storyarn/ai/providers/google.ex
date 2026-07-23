defmodule Storyarn.AI.Providers.Google do
  @moduledoc """
  Google Gemini BYOK adapter (AI Studio keys, not Vertex AI).

  Auth uses the `x-goog-api-key` header rather than Google's `?key=` query
  param so the key never appears in a URL. Google reports an invalid key as
  `400 API_KEY_INVALID` instead of 401, hence the local classify override.
  Model discovery requests Google's documented 1,000-item page instead of the
  50-item default so curated image and speech entries are not hidden.

  See `docs/features/ai-integrations/PROVIDERS.md` for endpoint details and
  why Vertex AI OAuth stayed in the backlog.
  """
  @behaviour Storyarn.AI.Provider

  alias Storyarn.AI.Providers.KeyValidation

  @base_url "https://generativelanguage.googleapis.com"

  @impl true
  def metadata do
    %{
      id: :google,
      name: "Google Gemini",
      key_generation_url: "https://aistudio.google.com/apikey",
      docs_url: "https://ai.google.dev/gemini-api/docs/api-key",
      key_placeholder: "AIza...",
      capabilities: [:translation, :suggestions, :tasks, :images, :speech]
    }
  end

  @impl true
  def validate_key(api_key) when is_binary(api_key) do
    __MODULE__
    |> KeyValidation.get(
      default_base_url: @base_url,
      url: "/v1beta/models",
      headers: [{"x-goog-api-key", api_key}],
      params: [pageSize: 1000]
    )
    |> classify()
  end

  defp classify({:ok, %Req.Response{status: 400}}), do: {:error, :invalid_key}
  defp classify(result), do: KeyValidation.classify(result)
end
