defmodule Storyarn.AI.InferenceProviders.Personal.Google do
  @moduledoc "Gemini OpenAI-compatibility adapter for actor-owned AI Studio keys."
  @behaviour Storyarn.AI.InferenceProvider

  alias Storyarn.AI.InferenceProviders.OpenAICompatible

  @impl true
  def generate(credential, request), do: OpenAICompatible.generate(__MODULE__, credential, request)
end
