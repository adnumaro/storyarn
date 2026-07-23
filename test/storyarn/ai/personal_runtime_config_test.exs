defmodule Storyarn.AI.PersonalRuntimeConfigTest do
  use ExUnit.Case, async: false

  alias Storyarn.AI.CredentialResolver
  alias Storyarn.AI.CredentialResolver.Composite
  alias Storyarn.AI.CredentialResolver.Personal
  alias Storyarn.AI.InferenceProviders
  alias Storyarn.AI.InferenceProviders.Personal.Anthropic
  alias Storyarn.AI.InferenceProviders.Personal.DeepSeek
  alias Storyarn.AI.InferenceProviders.Personal.Google
  alias Storyarn.AI.InferenceProviders.Personal.Mistral
  alias Storyarn.AI.InferenceProviders.Personal.Moonshot
  alias Storyarn.AI.InferenceProviders.Personal.OpenAI
  alias Storyarn.AI.ModelCatalog
  alias Storyarn.AI.PersonalConsents
  alias Storyarn.AI.PersonalProviders
  alias Storyarn.AI.RouteResolver

  @provider_endpoint_keys ~w(
    STORYARN_AI_PERSONAL_ANTHROPIC_ENDPOINT
    STORYARN_AI_PERSONAL_OPENAI_ENDPOINT
    STORYARN_AI_PERSONAL_GOOGLE_ENDPOINT
    STORYARN_AI_PERSONAL_MOONSHOT_ENDPOINT
    STORYARN_AI_PERSONAL_MISTRAL_ENDPOINT
    STORYARN_AI_PERSONAL_DEEPSEEK_ENDPOINT
  )

  @keys [
          "STORYARN_AI_PERSONAL_BYOK_ENABLED",
          "STORYARN_AI_PERSONAL_CONSENT_VERSION",
          "STORYARN_AI_MANAGED_ENABLED"
        ] ++ @provider_endpoint_keys

  setup do
    original = Map.new(@keys, &{&1, System.get_env(&1)})
    Enum.each(@keys, &System.delete_env/1)

    System.put_env("STORYARN_AI_PERSONAL_CONSENT_VERSION", "personal-egress-v1")

    on_exit(fn ->
      Enum.each(original, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end)
  end

  test "personal BYOK is configured without a second runtime feature switch" do
    config = runtime_storyarn_config()

    assert Keyword.fetch!(config, CredentialResolver) == Composite

    assert config
           |> Keyword.fetch!(Composite)
           |> Keyword.fetch!(:adapters) == %{personal_byok: Personal}

    assert config
           |> Keyword.fetch!(InferenceProviders)
           |> Keyword.fetch!(:providers) == %{
             "anthropic" => Anthropic,
             "deepseek" => DeepSeek,
             "google" => Google,
             "mistral" => Mistral,
             "moonshot" => Moonshot,
             "openai" => OpenAI
           }

    assert config
           |> Keyword.fetch!(PersonalProviders)
           |> Keyword.fetch!(:providers) == %{
             "anthropic" => %{
               processing_location: "provider-controlled"
             },
             "deepseek" => %{
               processing_location: "provider-controlled"
             },
             "google" => %{
               processing_location: "provider-controlled"
             },
             "mistral" => %{
               processing_location: "provider-controlled"
             },
             "moonshot" => %{
               processing_location: "provider-controlled"
             },
             "openai" => %{
               processing_location: "provider-controlled"
             }
           }

    assert config
           |> Keyword.fetch!(PersonalConsents)
           |> Keyword.fetch!(:policy_text_version) == "personal-egress-v1"

    openai_config = Keyword.fetch!(config, OpenAI)
    assert openai_config[:endpoint] == "https://api.openai.com/v1/chat/completions"
    assert openai_config[:request_overrides] == %{store: false}

    refute Keyword.has_key?(config, ModelCatalog)
    refute Keyword.has_key?(config, RouteResolver)
    refute Keyword.has_key?(config, Storyarn.AI.TaskRegistry)
  end

  test "endpoint overrides do not select or replace a default model" do
    System.put_env("STORYARN_AI_PERSONAL_OPENAI_ENDPOINT", "https://proxy.test/v1/chat/completions")

    config = runtime_storyarn_config()

    assert config
           |> Keyword.fetch!(OpenAI)
           |> Keyword.fetch!(:endpoint) == "https://proxy.test/v1/chat/completions"

    refute config
           |> Keyword.fetch!(PersonalProviders)
           |> Keyword.fetch!(:providers)
           |> Map.fetch!("openai")
           |> Map.has_key?(:model)
  end

  test "the removed legacy lane switch cannot disable personal provider configuration" do
    System.put_env("STORYARN_AI_PERSONAL_BYOK_ENABLED", "false")
    config = runtime_storyarn_config()

    assert Keyword.fetch!(config, CredentialResolver) == Composite
    assert Keyword.has_key?(config, InferenceProviders)
    assert Keyword.has_key?(config, PersonalProviders)
    assert Keyword.has_key?(config, PersonalConsents)
  end

  defp runtime_storyarn_config do
    "config/runtime.exs"
    |> Config.Reader.read!(env: :dev)
    |> Keyword.fetch!(:storyarn)
  end
end
