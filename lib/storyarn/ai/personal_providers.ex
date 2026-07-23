defmodule Storyarn.AI.PersonalProviders do
  @moduledoc """
  Curated Slice-4 provider routes.

  A connected account proves only that a key is valid. This registry is the
  server-owned allowlist of providers, models and structured-output modes that
  Storyarn is prepared to execute before Slice 5 adds a model catalog.
  """

  alias Storyarn.AI.ConfigMap
  alias Storyarn.AI.Providers

  @response_modes ~w(json_schema json_object)

  @spec fetch(String.t()) :: {:ok, map()} | {:error, :provider_unavailable}
  def fetch(provider) when is_binary(provider) do
    with {:ok, adapter} <- Providers.adapter_for(provider),
         config when is_map(config) <- Map.get(configured(), provider),
         {:ok, normalized} <- normalize(provider, config) do
      {:ok, Map.put(normalized, :metadata, adapter.metadata())}
    else
      _unavailable -> {:error, :provider_unavailable}
    end
  end

  def fetch(_provider), do: {:error, :provider_unavailable}

  @spec for_capability(atom()) :: [map()]
  def for_capability(capability) when is_atom(capability) do
    configured()
    |> Map.keys()
    |> Enum.sort()
    |> Enum.flat_map(&provider_for_capability(&1, capability))
  end

  def for_capability(_capability), do: []

  defp provider_for_capability(provider, capability) do
    case fetch(provider) do
      {:ok, %{metadata: %{capabilities: capabilities}} = config} ->
        if capability in capabilities, do: [config], else: []

      {:error, :provider_unavailable} ->
        []
    end
  end

  defp configured do
    :storyarn
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:providers, %{})
    |> normalize_provider_map()
  end

  defp normalize_provider_map(value) when is_map(value) do
    Map.new(value, fn {provider, config} -> {to_string(provider), ConfigMap.normalize(config)} end)
  end

  defp normalize_provider_map(_value), do: %{}

  defp normalize(provider, config) do
    model = config["model"]
    response_mode = config["response_mode"]
    processing_location = config["processing_location"]

    if nonempty?(model) and response_mode in @response_modes and nonempty?(processing_location) do
      {:ok,
       %{
         provider: provider,
         model: model,
         response_mode: response_mode,
         processing_location: processing_location
       }}
    else
      {:error, :provider_unavailable}
    end
  end

  defp nonempty?(value), do: is_binary(value) and String.trim(value) != ""
end
