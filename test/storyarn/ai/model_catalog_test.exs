defmodule Storyarn.AI.ModelCatalogTest do
  use ExUnit.Case, async: false

  alias Storyarn.AI.Integration
  alias Storyarn.AI.ModelCatalog
  alias Storyarn.AI.ModelCatalog.Entry

  test "loads validated, versioned model contracts from operator configuration" do
    assert {:ok, entry} = ModelCatalog.fetch("openai", "personal-deterministic-v1")

    assert entry.catalog_version == 1
    assert entry.capabilities == [:translation, :suggestions, :tasks]
    assert entry.modalities == [:text]
    assert entry.structured_output == :json_schema
    assert entry.processing_locations == ["provider-controlled"]
    refute entry.deprecated?

    assert ModelCatalog.for_capability(:suggestions) == [entry]
    assert ModelCatalog.for_capability(:images) == []
  end

  test "provider discovery narrows the operator catalog without expanding it" do
    {:ok, entry} = ModelCatalog.fetch("openai", "personal-deterministic-v1")

    assert :ok = ModelCatalog.authorize(entry, %Integration{available_models: nil})

    assert :ok =
             ModelCatalog.authorize(entry, %Integration{
               available_models: ["models/personal-deterministic-v1", "provider-unknown-model"]
             })

    assert {:error, :model_unavailable} =
             ModelCatalog.authorize(entry, %Integration{
               available_models: ["provider-unknown-model"]
             })

    assert {:error, :model_unavailable} =
             ModelCatalog.fetch("openai", "provider-unknown-model")
  end

  test "rejects unknown enum values without creating atoms from configuration" do
    attrs = %{
      provider: "openai",
      model: "unsafe",
      catalog_version: 1,
      capabilities: ["invented_capability"],
      modalities: ["text"],
      structured_output: "json_schema",
      processing_locations: ["provider-controlled"],
      deprecated: false
    }

    assert {:error, :invalid_model_catalog_entry} = Entry.new(attrs)
  end

  test "the highest catalog version supersedes older contracts for the same model" do
    original = Application.get_env(:storyarn, ModelCatalog, [])

    base = %{
      provider: "openai",
      model: "versioned-model",
      capabilities: [:suggestions],
      modalities: [:text],
      structured_output: :json_schema,
      processing_locations: ["provider-controlled"],
      deprecated: false
    }

    Application.put_env(:storyarn, ModelCatalog,
      models: [
        Map.put(base, :catalog_version, 1),
        base
        |> Map.put(:catalog_version, 2)
        |> Map.put(:deprecated, true)
      ]
    )

    on_exit(fn -> Application.put_env(:storyarn, ModelCatalog, original) end)

    assert {:ok, entry} = ModelCatalog.fetch("openai", "versioned-model")
    assert entry.catalog_version == 2
    assert entry.deprecated?
    assert ModelCatalog.for_capability(:suggestions) == []
    assert ModelCatalog.for_capability(:suggestions, include_deprecated: true) == [entry]
  end

  test "public summaries contain routing metadata but no credentials or account identity" do
    assert [summary] = ModelCatalog.public_for_provider("openai")
    assert summary.model == "personal-deterministic-v1"
    assert summary.catalog_version == 1
    assert summary.capabilities == ["translation", "suggestions", "tasks"]
    refute Map.has_key?(summary, :api_key)
    refute Map.has_key?(summary, :user_id)
  end
end
