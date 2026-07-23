defmodule Storyarn.AI.InferenceProviders.Together do
  @moduledoc "Together structured-output adapter for the managed Storyarn AI route."
  @behaviour Storyarn.AI.InferenceProvider

  alias Storyarn.AI.InferenceProviders.OpenAICompatible

  @impl true
  def generate(credential, request) do
    OpenAICompatible.generate(__MODULE__, credential, request)
  end
end
