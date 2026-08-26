defmodule Storyarn.AI.InferenceProviders.Personal.Mistral do
  @moduledoc "Mistral structured-text adapter for actor-owned API keys."
  @behaviour Storyarn.AI.InferenceProvider

  alias Storyarn.AI.InferenceProviders.OpenAICompatible

  @impl true
  def generate(credential, request), do: OpenAICompatible.generate(__MODULE__, credential, request)
end
