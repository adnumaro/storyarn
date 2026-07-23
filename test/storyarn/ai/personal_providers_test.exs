defmodule Storyarn.AI.PersonalProvidersTest do
  use ExUnit.Case, async: false

  alias Storyarn.AI.ModelCatalog
  alias Storyarn.AI.PersonalProviders

  setup do
    original_catalog = Application.fetch_env(:storyarn, ModelCatalog)
    original_providers = Application.fetch_env(:storyarn, PersonalProviders)

    Application.put_env(:storyarn, ModelCatalog,
      models: [
        model("model-a"),
        model("model-b"),
        media_model("image-model", :images, :openai_images, :image),
        media_model("speech-model", :speech, :openai_speech, :audio)
      ]
    )

    Application.put_env(:storyarn, PersonalProviders,
      providers: %{
        "openai" => %{
          processing_location: "provider-controlled"
        }
      }
    )

    on_exit(fn ->
      restore_env(ModelCatalog, original_catalog)
      restore_env(PersonalProviders, original_providers)
    end)
  end

  test "exposes every supported model without inventing a provider default" do
    assert {:error, :provider_unavailable} = PersonalProviders.fetch("openai")

    assert {:ok, first} = PersonalProviders.fetch("openai", "model-a")
    assert {:ok, second} = PersonalProviders.fetch("openai", "model-b")

    assert first.model == "model-a"
    assert second.model == "model-b"
    assert first.response_mode == "json_schema"

    assert :suggestions
           |> PersonalProviders.for_capability()
           |> Enum.map(& &1.model) == ["model-a", "model-b"]
  end

  test "does not execute a provider-discovered model outside Storyarn's catalog" do
    assert {:error, :provider_unavailable} =
             PersonalProviders.fetch("openai", "provider-only-model")
  end

  test "configuration-only image and speech models can be selected but never become execution routes" do
    for {capability, model} <- [images: "image-model", speech: "speech-model"] do
      assert {:ok, config} = PersonalProviders.fetch_configurable("openai", model)
      assert config.catalog.implementation_status == :configuration_only
      assert config.response_mode == "none"

      assert {:error, :provider_unavailable} =
               PersonalProviders.fetch("openai", model)

      assert capability
             |> PersonalProviders.configurable_for_capability()
             |> Enum.map(& &1.model) == [model]

      assert PersonalProviders.for_capability(capability) == []
    end
  end

  defp model(name) do
    %{
      provider: "openai",
      model: name,
      catalog_version: 1,
      capabilities: [:translation, :suggestions, :tasks],
      input_modalities: [:text],
      output_modalities: [:text],
      structured_output: :json_schema,
      api_family: :structured_text,
      implementation_status: :executable,
      release_stage: :stable,
      context_window: 128_000,
      max_output_tokens: 8_192,
      processing_locations: ["provider-controlled"],
      pricing_version: nil,
      deprecated: false
    }
  end

  defp media_model(name, capability, api_family, output_modality) do
    %{
      provider: "openai",
      model: name,
      catalog_version: 1,
      capabilities: [capability],
      input_modalities: [:text],
      output_modalities: [output_modality],
      structured_output: :none,
      api_family: api_family,
      implementation_status: :configuration_only,
      release_stage: :stable,
      context_window: nil,
      max_output_tokens: nil,
      processing_locations: ["provider-controlled"],
      pricing_version: nil,
      deprecated: false
    }
  end

  defp restore_env(module, {:ok, config}), do: Application.put_env(:storyarn, module, config)
  defp restore_env(module, :error), do: Application.delete_env(:storyarn, module)
end
