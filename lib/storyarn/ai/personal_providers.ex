defmodule Storyarn.AI.PersonalProviders do
  @moduledoc """
  Operator-configured personal provider routes backed by the model catalog.

  A connected account proves only that a key is valid. This registry owns
  operator/runtime provider availability and processing location, while
  `Storyarn.AI.ModelCatalog` owns per-model capabilities, API family,
  structured-output mode, implementation state, and lifecycle.

  Configuration-only media models may be selected as future role preferences,
  but `fetch/2` and `for_capability/1` deliberately exclude them until a
  modality-specific execution adapter ships.
  """

  alias Storyarn.AI.ConfigMap
  alias Storyarn.AI.InferenceProviders
  alias Storyarn.AI.Integration
  alias Storyarn.AI.ModelCatalog
  alias Storyarn.AI.Providers

  @executable_response_modes ~w(json_schema json_object)

  @spec fetch(String.t()) :: {:ok, map()} | {:error, :provider_unavailable}
  def fetch(provider) when is_binary(provider) do
    # Never infer a default model from catalog order. This arity is retained for
    # explicit operator/test overrides that name a model in provider config.
    with config when is_map(config) <- Map.get(configured(), provider),
         model when is_binary(model) <- config["model"] do
      fetch(provider, model)
    else
      _unavailable -> {:error, :provider_unavailable}
    end
  end

  def fetch(_provider), do: {:error, :provider_unavailable}

  @spec fetch(String.t(), String.t()) :: {:ok, map()} | {:error, :provider_unavailable}
  def fetch(provider, model) when is_binary(provider) and is_binary(model) do
    with {:ok, config} <- fetch_configurable(provider, model),
         true <- config.catalog.implementation_status == :executable,
         true <- config.catalog.api_family == :structured_text,
         true <- config.response_mode in @executable_response_modes,
         {:ok, _adapter} <- InferenceProviders.fetch(provider) do
      {:ok, config}
    else
      _unavailable -> {:error, :provider_unavailable}
    end
  end

  def fetch(_provider, _model), do: {:error, :provider_unavailable}

  @doc """
  Returns a curated model that can be saved as a role preference.

  Unlike `fetch/2`, this includes `:configuration_only` media entries. It never
  implies that an executable task or media adapter exists.
  """
  @spec fetch_configurable(String.t(), String.t()) ::
          {:ok, map()} | {:error, :provider_unavailable}
  def fetch_configurable(provider, model) when is_binary(provider) and is_binary(model) do
    with {:ok, adapter} <- Providers.adapter_for(provider),
         config when is_map(config) <- Map.get(configured(), provider),
         {:ok, normalized} <- normalize_configurable(provider, model, config) do
      {:ok, Map.put(normalized, :metadata, adapter.metadata())}
    else
      _unavailable -> {:error, :provider_unavailable}
    end
  end

  def fetch_configurable(_provider, _model), do: {:error, :provider_unavailable}

  @spec for_capability(atom()) :: [map()]
  def for_capability(capability) when is_atom(capability) do
    configured()
    |> Map.keys()
    |> Enum.sort()
    |> Enum.flat_map(&provider_for_capability(&1, capability))
  end

  def for_capability(_capability), do: []

  @spec configurable_for_capability(atom()) :: [map()]
  def configurable_for_capability(capability) when is_atom(capability) do
    configured()
    |> Map.keys()
    |> Enum.sort()
    |> Enum.flat_map(&configurable_provider_for_capability(&1, capability))
  end

  def configurable_for_capability(_capability), do: []

  defp provider_for_capability(provider, capability) do
    provider
    |> ModelCatalog.for_provider()
    |> Enum.flat_map(&config_for_capability(provider, &1, capability))
  end

  defp config_for_capability(provider, catalog, capability) do
    case fetch(provider, catalog.model) do
      {:ok, config} -> include_capability(config, capability)
      {:error, :provider_unavailable} -> []
    end
  end

  defp configurable_provider_for_capability(provider, capability) do
    provider
    |> ModelCatalog.for_provider()
    |> Enum.flat_map(fn catalog ->
      case fetch_configurable(provider, catalog.model) do
        {:ok, config} -> include_capability(config, capability)
        {:error, :provider_unavailable} -> []
      end
    end)
  end

  defp include_capability(%{catalog: %{capabilities: capabilities}} = config, capability),
    do: if(capability in capabilities, do: [config], else: [])

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

  defp normalize_configurable(provider, model, config) do
    processing_location = config["processing_location"]

    with true <- nonempty?(model),
         true <- nonempty?(processing_location),
         {:ok, catalog} <- ModelCatalog.fetch(provider, model),
         true <- processing_location in catalog.processing_locations do
      {:ok,
       %{
         provider: provider,
         model: model,
         response_mode: Atom.to_string(catalog.structured_output),
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

  defp nonempty?(value), do: is_binary(value) and String.trim(value) != ""
end
