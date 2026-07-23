defmodule Storyarn.AI.ModelCatalogTest do
  use ExUnit.Case, async: false

  alias Storyarn.AI.Integration
  alias Storyarn.AI.ModelCatalog
  alias Storyarn.AI.ModelCatalog.Defaults
  alias Storyarn.AI.ModelCatalog.Entry

  test "ships a versioned catalog for every supported personal provider" do
    entries = entries_from(Defaults.models())

    assert length(entries) == 22

    assert entries
           |> Enum.group_by(& &1.provider)
           |> Map.new(fn {provider, models} -> {provider, Enum.map(models, & &1.model)} end) == %{
             "anthropic" => [
               "claude-fable-5",
               "claude-opus-4-8",
               "claude-sonnet-5",
               "claude-haiku-4-5-20251001"
             ],
             "deepseek" => ["deepseek-v4-pro", "deepseek-v4-flash"],
             "google" => [
               "gemini-3.6-flash",
               "gemini-3.5-flash-lite",
               "gemini-3.1-flash-lite-image",
               "gemini-3.1-flash-image",
               "gemini-3-pro-image",
               "gemini-3.1-flash-tts-preview"
             ],
             "mistral" => ["mistral-large-2512", "mistral-small-2603"],
             "moonshot" => ["kimi-k3", "kimi-k2.6"],
             "openai" => [
               "gpt-5.6-sol",
               "gpt-5.6-terra",
               "gpt-5.6-luna",
               "gpt-image-2",
               "tts-1",
               "tts-1-hd"
             ]
           }

    text_entries = Enum.filter(entries, &(&1.api_family == :structured_text))
    media_entries = Enum.reject(entries, &(&1.api_family == :structured_text))

    assert Enum.all?(text_entries, fn entry ->
             entry.catalog_version == 1 and
               entry.capabilities == [:translation, :suggestions, :tasks] and
               entry.input_modalities == [:text] and
               entry.output_modalities == [:text] and
               entry.implementation_status == :executable and
               entry.release_stage == :stable and
               entry.processing_locations == ["provider-controlled"] and
               not entry.deprecated?
           end)

    assert Enum.all?(media_entries, fn entry ->
             entry.catalog_version == 1 and
               entry.structured_output == :none and
               entry.implementation_status == :configuration_only and
               entry.processing_locations == ["provider-controlled"] and
               not entry.deprecated?
           end)

    assert media_entries
           |> Enum.filter(&(:images in &1.capabilities))
           |> Enum.sort_by(&{&1.provider, &1.model})
           |> Enum.map(&{&1.provider, &1.model}) == [
             {"google", "gemini-3-pro-image"},
             {"google", "gemini-3.1-flash-image"},
             {"google", "gemini-3.1-flash-lite-image"},
             {"openai", "gpt-image-2"}
           ]

    assert media_entries
           |> Enum.filter(&(:speech in &1.capabilities))
           |> Enum.sort_by(&{&1.provider, &1.model})
           |> Enum.map(&{&1.provider, &1.model}) == [
             {"google", "gemini-3.1-flash-tts-preview"},
             {"openai", "tts-1"},
             {"openai", "tts-1-hd"}
           ]

    refute Enum.any?(entries, &(&1.model == "gpt-4o-mini-tts"))

    assert Enum.all?(
             Enum.filter(media_entries, &(&1.api_family == :google_interactions_image)),
             &(MapSet.new(&1.output_modalities) == MapSet.new([:text, :image]))
           )

    assert Enum.all?(
             Enum.filter(media_entries, &(&1.api_family == :openai_images)),
             &(&1.output_modalities == [:image])
           )

    assert Enum.find(entries, &(&1.model == "gemini-3.1-flash-tts-preview")).release_stage ==
             :preview

    assert Enum.all?(
             Enum.filter(
               text_entries,
               &(&1.provider in ~w(openai anthropic google mistral))
             ),
             &(&1.structured_output == :json_schema)
           )

    assert Enum.all?(
             Enum.filter(text_entries, &(&1.provider in ~w(moonshot deepseek))),
             &(&1.structured_output == :json_object)
           )

    assert_limits(entries, "openai", 1_050_000, 128_000)

    entries
    |> Enum.reject(&(&1.model == "claude-haiku-4-5-20251001"))
    |> Enum.filter(&(&1.provider == "anthropic"))
    |> assert_limits(1_000_000, 128_000)

    entries
    |> Enum.filter(&(&1.model == "claude-haiku-4-5-20251001"))
    |> assert_limits(200_000, 64_000)

    assert_limits(entries, "google", 1_048_576, 65_536)
  end

  test "uses shipped defaults unless application configuration explicitly overrides them" do
    original = Application.fetch_env(:storyarn, ModelCatalog)

    on_exit(fn -> restore_env(ModelCatalog, original) end)

    Application.delete_env(:storyarn, ModelCatalog)

    assert {:ok, default} = ModelCatalog.fetch("openai", "gpt-5.6-sol")
    assert default.context_window == 1_050_000
    assert default.max_output_tokens == 128_000

    Application.put_env(:storyarn, ModelCatalog, models: [])

    assert ModelCatalog.all() == []
    assert {:error, :model_unavailable} = ModelCatalog.fetch("openai", "gpt-5.6-sol")
  end

  test "loads validated, versioned model contracts from operator configuration" do
    assert {:ok, entry} = ModelCatalog.fetch("openai", "personal-deterministic-v1")

    assert entry.catalog_version == 1
    assert entry.capabilities == [:translation, :suggestions, :tasks]
    assert entry.input_modalities == [:text]
    assert entry.output_modalities == [:text]
    assert entry.structured_output == :json_schema
    assert entry.api_family == :structured_text
    assert entry.implementation_status == :executable
    assert entry.release_stage == :stable
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
      input_modalities: ["text"],
      output_modalities: ["text"],
      structured_output: "json_schema",
      api_family: "structured_text",
      implementation_status: "executable",
      release_stage: "stable",
      processing_locations: ["provider-controlled"],
      deprecated: false
    }

    assert {:error, :invalid_model_catalog_entry} = Entry.new(attrs)
  end

  test "configuration cannot promote multimedia models before an execution adapter ships" do
    for attrs <- [
          %{
            provider: "openai",
            model: "unsafe-image-route",
            catalog_version: 1,
            capabilities: [:images],
            input_modalities: [:text, :image],
            output_modalities: [:image],
            structured_output: :none,
            api_family: :openai_images,
            implementation_status: :executable,
            release_stage: :stable,
            processing_locations: ["provider-controlled"],
            deprecated: false
          },
          %{
            provider: "openai",
            model: "unsafe-speech-route",
            catalog_version: 1,
            capabilities: [:speech],
            input_modalities: [:text],
            output_modalities: [:audio],
            structured_output: :none,
            api_family: :openai_speech,
            implementation_status: :executable,
            release_stage: :stable,
            processing_locations: ["provider-controlled"],
            deprecated: false
          }
        ] do
      assert {:error, :invalid_model_catalog_entry} = Entry.new(attrs)
    end
  end

  test "google image contracts expose both text and image output capabilities" do
    attrs = %{
      provider: "google",
      model: "google-image-contract",
      catalog_version: 1,
      capabilities: [:images],
      input_modalities: [:text, :image],
      output_modalities: [:image],
      structured_output: :none,
      api_family: :google_interactions_image,
      implementation_status: :configuration_only,
      release_stage: :stable,
      processing_locations: ["provider-controlled"],
      deprecated: false
    }

    assert {:error, :invalid_model_catalog_entry} = Entry.new(attrs)

    assert {:ok, entry} =
             attrs
             |> Map.put(:output_modalities, [:image, :text])
             |> Entry.new()

    assert MapSet.new(entry.output_modalities) == MapSet.new([:text, :image])
  end

  test "the highest catalog version supersedes older contracts for the same model" do
    original = Application.get_env(:storyarn, ModelCatalog, [])

    base = %{
      provider: "openai",
      model: "versioned-model",
      capabilities: [:suggestions],
      input_modalities: [:text],
      output_modalities: [:text],
      structured_output: :json_schema,
      api_family: :structured_text,
      implementation_status: :executable,
      release_stage: :stable,
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
    assert summary.input_modalities == ["text"]
    assert summary.output_modalities == ["text"]
    assert summary.api_family == "structured_text"
    assert summary.implementation_status == "executable"
    assert summary.release_stage == "stable"
    refute Map.has_key?(summary, :api_key)
    refute Map.has_key?(summary, :user_id)
  end

  defp entries_from(models) do
    Enum.map(models, fn attrs ->
      assert {:ok, entry} = Entry.new(attrs)
      entry
    end)
  end

  defp assert_limits(entries, provider, context_window, max_output_tokens) do
    entries
    |> Enum.filter(&(&1.provider == provider and &1.implementation_status == :executable))
    |> assert_limits(context_window, max_output_tokens)
  end

  defp assert_limits(entries, context_window, max_output_tokens) do
    assert entries != []

    assert Enum.all?(
             entries,
             &(&1.context_window == context_window and
                 &1.max_output_tokens == max_output_tokens)
           )
  end

  defp restore_env(module, {:ok, config}), do: Application.put_env(:storyarn, module, config)
  defp restore_env(module, :error), do: Application.delete_env(:storyarn, module)
end
