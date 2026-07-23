defmodule Storyarn.AI.PersonalProviders do
  @moduledoc """
  Operator-configured personal provider routes backed by the model catalog.

  A connected account proves only that a key is valid. This registry is the
  server-owned allowlist of endpoint/response-mode configuration, while
  `Storyarn.AI.ModelCatalog` owns per-model capabilities and lifecycle.
  """

  alias Storyarn.AI.ConfigMap
  alias Storyarn.AI.Integration
  alias Storyarn.AI.ModelCatalog
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
      {:ok, %{catalog: %{capabilities: capabilities}} = config} ->
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

    with true <- nonempty?(model),
         true <- response_mode in @response_modes,
         true <- nonempty?(processing_location),
         {:ok, catalog} <- ModelCatalog.fetch(provider, model),
         true <- response_mode_matches?(response_mode, catalog.structured_output),
         true <- processing_location in catalog.processing_locations do
      {:ok,
       %{
         provider: provider,
         model: model,
         response_mode: response_mode,
         processing_location: processing_location,
         catalog: catalog
       }}
    else
      _invalid -> {:error, :provider_unavailable}
    end
  end

  @spec model_status(map(), Integration.t()) :: :ready | :model_deprecated | :model_unavailable
  def model_status(%{catalog: catalog}, %Integration{} = integration) do
    case ModelCatalog.authorize(catalog, integration) do
      :ok -> :ready
      {:error, reason} -> reason
    end
  end

  defp response_mode_matches?("json_schema", :json_schema), do: true
  defp response_mode_matches?("json_object", :json_object), do: true
  defp response_mode_matches?(_response_mode, _structured_output), do: false

  defp nonempty?(value), do: is_binary(value) and String.trim(value) != ""
end
