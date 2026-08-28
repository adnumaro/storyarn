defmodule Storyarn.AI.Providers do
  @moduledoc """
  Registry of AI provider adapters.

  New providers are added by implementing `Storyarn.AI.Provider`, declaring
  their stable identifier and position in `Integrations.Rules.ProviderIds`, and
  mapping that identifier to the adapter below. UI order and dispatch derive
  from those two pieces.
  """

  alias Storyarn.AI.Integrations.Rules.ProviderIds
  alias Storyarn.AI.Provider
  alias Storyarn.AI.Providers.Anthropic
  alias Storyarn.AI.Providers.DeepL
  alias Storyarn.AI.Providers.DeepSeek
  alias Storyarn.AI.Providers.Google
  alias Storyarn.AI.Providers.Mistral
  alias Storyarn.AI.Providers.Moonshot
  alias Storyarn.AI.Providers.OpenAI

  @adapters %{
    anthropic: Anthropic,
    openai: OpenAI,
    google: Google,
    moonshot: Moonshot,
    mistral: Mistral,
    deepseek: DeepSeek,
    deepl: DeepL
  }

  @doc "All adapter modules registered with the application."
  @spec adapters() :: [module()]
  def adapters, do: Enum.map(ProviderIds.known_ids(), &Map.fetch!(@adapters, &1))

  @doc "All provider identifiers (atoms)."
  @spec known_ids() :: [Provider.id()]
  defdelegate known_ids(), to: ProviderIds

  @doc "Look up the adapter module for a provider identifier."
  @spec adapter_for(Provider.id() | String.t()) :: {:ok, module()} | {:error, :unknown_provider}
  def adapter_for(id) when is_atom(id) do
    with {:ok, provider_id} <- ProviderIds.fetch(id) do
      {:ok, Map.fetch!(@adapters, provider_id)}
    end
  end

  def adapter_for(id) when is_binary(id) do
    with {:ok, provider_id} <- ProviderIds.fetch(id) do
      adapter_for(provider_id)
    end
  end

  @doc "Metadata list for every provider — used to render the settings grid."
  @spec metadata_list() :: [Provider.metadata()]
  def metadata_list, do: Enum.map(adapters(), & &1.metadata())
end
