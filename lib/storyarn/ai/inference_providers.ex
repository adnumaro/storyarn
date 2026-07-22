defmodule Storyarn.AI.InferenceProviders do
  @moduledoc "Operational registry for inference adapters; separate from connectable provider cards."

  @spec fetch(String.t()) :: {:ok, module()} | {:error, :provider_unavailable}
  def fetch(provider) when is_binary(provider) do
    providers =
      :storyarn
      |> Application.get_env(__MODULE__, [])
      |> Keyword.get(:providers, %{})

    case Map.fetch(providers, provider) do
      {:ok, module} when is_atom(module) ->
        if Code.ensure_loaded?(module) and function_exported?(module, :generate, 2),
          do: {:ok, module},
          else: {:error, :provider_unavailable}

      _missing ->
        {:error, :provider_unavailable}
    end
  end

  def fetch(_provider), do: {:error, :provider_unavailable}
end
