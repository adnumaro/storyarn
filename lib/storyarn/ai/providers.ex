defmodule Storyarn.AI.Providers do
  @moduledoc """
  Registry of AI provider adapters.

  New providers are added by implementing `Storyarn.AI.Provider` and appending
  the adapter module to `@adapters`. Everything else (UI card list, database
  provider enum, dispatch) derives from this list.
  """

  alias Storyarn.AI.Provider
  alias Storyarn.AI.Providers.Anthropic
  alias Storyarn.AI.Providers.DeepSeek
  alias Storyarn.AI.Providers.Google
  alias Storyarn.AI.Providers.Mistral
  alias Storyarn.AI.Providers.Moonshot
  alias Storyarn.AI.Providers.OpenAI

  # Order defines the settings-grid card order (not alphabetical on purpose).
  @adapters [Anthropic, OpenAI, Google, Moonshot, Mistral, DeepSeek]

  @doc "All adapter modules registered with the application."
  @spec adapters() :: [module()]
  def adapters, do: @adapters

  @doc "All provider identifiers (atoms)."
  @spec known_ids() :: [Provider.id()]
  def known_ids, do: Enum.map(@adapters, & &1.metadata().id)

  @doc "Look up the adapter module for a provider identifier."
  @spec adapter_for(Provider.id() | String.t()) :: {:ok, module()} | {:error, :unknown_provider}
  def adapter_for(id) when is_atom(id) do
    Enum.find_value(@adapters, {:error, :unknown_provider}, fn adapter ->
      if adapter.metadata().id == id, do: {:ok, adapter}
    end)
  end

  def adapter_for(id) when is_binary(id) do
    case Enum.find(known_ids(), &(Atom.to_string(&1) == id)) do
      nil -> {:error, :unknown_provider}
      atom -> adapter_for(atom)
    end
  end

  @doc "Metadata list for every provider — used to render the settings grid."
  @spec metadata_list() :: [Provider.metadata()]
  def metadata_list, do: Enum.map(@adapters, & &1.metadata())
end
