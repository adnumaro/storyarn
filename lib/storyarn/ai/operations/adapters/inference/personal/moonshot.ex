defmodule Storyarn.AI.InferenceProviders.Personal.Moonshot do
  @moduledoc "Moonshot OpenAI-compatible adapter for actor-owned API keys."
  @behaviour Storyarn.AI.InferenceProvider

  alias Storyarn.AI.InferenceProviders.OpenAICompatible

  @impl true
  def generate(credential, request), do: OpenAICompatible.generate(__MODULE__, credential, request)
end
