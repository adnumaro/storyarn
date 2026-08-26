defmodule Storyarn.AI.Integrations.Rules.ProviderIds do
  @moduledoc false

  alias Storyarn.AI.Provider

  # Domain order: this defines both the accepted persisted identifiers and
  # their order in provider-selection surfaces.
  @known_ids [:anthropic, :openai, :google, :moonshot, :mistral, :deepseek, :deepl]
  @known_strings Enum.map(@known_ids, &Atom.to_string/1)

  @spec known_ids() :: [Provider.id()]
  def known_ids, do: @known_ids

  @spec known_strings() :: [String.t()]
  def known_strings, do: @known_strings

  @spec fetch(Provider.id() | String.t()) :: {:ok, Provider.id()} | {:error, :unknown_provider}
  def fetch(id) when is_atom(id) do
    if id in @known_ids, do: {:ok, id}, else: {:error, :unknown_provider}
  end

  def fetch(id) when is_binary(id) do
    case Enum.find(@known_ids, &(Atom.to_string(&1) == id)) do
      nil -> {:error, :unknown_provider}
      provider_id -> {:ok, provider_id}
    end
  end
end
