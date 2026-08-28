defmodule Storyarn.AI.Integrations.Rules.ProviderIdsTest do
  use ExUnit.Case, async: true

  alias Storyarn.AI.Integrations.Rules.ProviderIds
  alias Storyarn.AI.Providers

  @provider_ids [:anthropic, :openai, :google, :moonshot, :mistral, :deepseek, :deepl]

  test "keeps accepted provider identifiers and adapter presentation order stable" do
    assert ProviderIds.known_ids() == @provider_ids
    assert ProviderIds.known_strings() == Enum.map(@provider_ids, &Atom.to_string/1)
    assert Providers.known_ids() == @provider_ids
    assert Enum.map(Providers.adapters(), & &1.metadata().id) == @provider_ids
    assert Enum.map(Providers.metadata_list(), & &1.id) == @provider_ids
  end
end
