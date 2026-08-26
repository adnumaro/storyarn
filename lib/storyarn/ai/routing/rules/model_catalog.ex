defmodule Storyarn.AI.ModelCatalog do
  @moduledoc """
  Operator-curated, versioned provider-model capability catalog.

  Provider discovery is treated only as an availability signal. The catalog
  remains the authority for what Storyarn is prepared to execute.
  """

  alias Storyarn.AI.Integration
  alias Storyarn.AI.ModelCatalog.Defaults
  alias Storyarn.AI.ModelCatalog.Entry

  @spec all() :: [Entry.t()]
  def all do
    configured_models()
    |> Enum.flat_map(fn attrs ->
      case Entry.new(attrs) do
        {:ok, entry} -> [entry]
        {:error, :invalid_model_catalog_entry} -> []
      end
    end)
    |> Enum.sort_by(&{&1.provider, &1.model, &1.catalog_version})
  end

  @spec fetch(String.t(), String.t()) :: {:ok, Entry.t()} | {:error, :model_unavailable}
  def fetch(provider, model) when is_binary(provider) and is_binary(model) do
    entry =
      all()
      |> Enum.filter(&(&1.provider == provider and &1.model == model))
      |> Enum.max_by(& &1.catalog_version, fn -> nil end)

    case entry do
      %Entry{} = entry -> {:ok, entry}
      nil -> {:error, :model_unavailable}
    end
  end

  def fetch(_provider, _model), do: {:error, :model_unavailable}

  @spec for_capability(atom(), keyword()) :: [Entry.t()]
  def for_capability(capability, opts \\ []) when is_atom(capability) do
    include_deprecated? = Keyword.get(opts, :include_deprecated, false)

    Enum.filter(current_entries(), fn entry ->
      capability in entry.capabilities and (include_deprecated? or not entry.deprecated?)
    end)
  end

  @spec for_provider(String.t(), keyword()) :: [Entry.t()]
  def for_provider(provider, opts \\ []) when is_binary(provider) do
    include_deprecated? = Keyword.get(opts, :include_deprecated, true)

    Enum.filter(current_entries(), fn entry ->
      entry.provider == provider and (include_deprecated? or not entry.deprecated?)
    end)
  end

  @spec authorize(Entry.t(), Integration.t()) ::
          :ok | {:error, :model_deprecated | :model_unavailable}
  def authorize(%Entry{deprecated?: true}, %Integration{}), do: {:error, :model_deprecated}

  def authorize(%Entry{}, %Integration{available_models: nil}), do: :ok

  def authorize(%Entry{} = entry, %Integration{available_models: models}) when is_list(models) do
    if entry.model in Enum.map(models, &normalize_discovered_model/1),
      do: :ok,
      else: {:error, :model_unavailable}
  end

  def authorize(%Entry{}, %Integration{}), do: {:error, :model_unavailable}

  @spec provider_status(Integration.t()) ::
          :ready | :connection_only | :model_deprecated | :model_unavailable
  def provider_status(%Integration{provider: provider} = integration) do
    entries = for_provider(provider)

    cond do
      entries == [] ->
        :connection_only

      Enum.any?(entries, &(authorize(&1, integration) == :ok)) ->
        :ready

      Enum.all?(entries, & &1.deprecated?) ->
        :model_deprecated

      true ->
        :model_unavailable
    end
  end

  @spec public_for_provider(String.t()) :: [map()]
  def public_for_provider(provider) do
    provider
    |> for_provider()
    |> Enum.map(&public_summary/1)
  end

  @spec public_summary(Entry.t()) :: map()
  def public_summary(%Entry{} = entry) do
    %{
      provider: entry.provider,
      model: entry.model,
      catalog_version: entry.catalog_version,
      capabilities: Enum.map(entry.capabilities, &Atom.to_string/1),
      input_modalities: Enum.map(entry.input_modalities, &Atom.to_string/1),
      output_modalities: Enum.map(entry.output_modalities, &Atom.to_string/1),
      structured_output: Atom.to_string(entry.structured_output),
      api_family: Atom.to_string(entry.api_family),
      implementation_status: Atom.to_string(entry.implementation_status),
      release_stage: Atom.to_string(entry.release_stage),
      context_window: entry.context_window,
      max_output_tokens: entry.max_output_tokens,
      processing_locations: entry.processing_locations,
      pricing_version: entry.pricing_version,
      deprecated: entry.deprecated?
    }
  end

  defp normalize_discovered_model(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.replace_prefix("models/", "")
  end

  defp normalize_discovered_model(_value), do: ""

  defp configured_models do
    case Application.get_env(:storyarn, __MODULE__) do
      config when is_list(config) ->
        case Keyword.fetch(config, :models) do
          {:ok, models} when is_list(models) -> models
          {:ok, _invalid} -> []
          :error -> Defaults.models()
        end

      _not_configured ->
        Defaults.models()
    end
  end

  defp current_entries do
    all()
    |> Enum.group_by(&{&1.provider, &1.model})
    |> Enum.map(fn {_identity, entries} -> Enum.max_by(entries, & &1.catalog_version) end)
    |> Enum.sort_by(&{&1.provider, &1.model})
  end
end
