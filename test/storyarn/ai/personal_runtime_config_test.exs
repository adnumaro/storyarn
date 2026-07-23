defmodule Storyarn.AI.PersonalRuntimeConfigTest do
  use ExUnit.Case, async: false

  alias Storyarn.AI.CredentialResolver
  alias Storyarn.AI.CredentialResolver.Composite
  alias Storyarn.AI.CredentialResolver.Personal
  alias Storyarn.AI.InferenceProviders
  alias Storyarn.AI.InferenceProviders.Personal.OpenAI
  alias Storyarn.AI.PersonalConsents
  alias Storyarn.AI.PersonalProviders
  alias Storyarn.AI.RouteResolver

  @provider_model_keys ~w(
    STORYARN_AI_PERSONAL_ANTHROPIC_MODEL
    STORYARN_AI_PERSONAL_OPENAI_MODEL
    STORYARN_AI_PERSONAL_GOOGLE_MODEL
    STORYARN_AI_PERSONAL_MOONSHOT_MODEL
    STORYARN_AI_PERSONAL_MISTRAL_MODEL
    STORYARN_AI_PERSONAL_DEEPSEEK_MODEL
  )

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
        ] ++ @provider_model_keys ++ @provider_endpoint_keys

  setup do
    original = Map.new(@keys, &{&1, System.get_env(&1)})
    Enum.each(@keys, &System.delete_env/1)

    System.put_env("STORYARN_AI_PERSONAL_BYOK_ENABLED", "true")
    System.put_env("STORYARN_AI_PERSONAL_CONSENT_VERSION", "personal-egress-v1")
    System.put_env("STORYARN_AI_PERSONAL_OPENAI_MODEL", "gpt-personal-test")

    on_exit(fn ->
      Enum.each(original, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end)
  end

  test "personal BYOK is configured independently with no managed route or task" do
    config = runtime_storyarn_config()

    assert Keyword.fetch!(config, CredentialResolver) == Composite

    assert config
           |> Keyword.fetch!(Composite)
           |> Keyword.fetch!(:adapters) == %{personal_byok: Personal}

    assert config
           |> Keyword.fetch!(InferenceProviders)
           |> Keyword.fetch!(:providers) == %{"openai" => OpenAI}

    assert config
           |> Keyword.fetch!(PersonalProviders)
           |> Keyword.fetch!(:providers) == %{
             "openai" => %{
               model: "gpt-personal-test",
               processing_location: "provider-controlled",
               response_mode: "json_schema"
             }
           }

    assert config
           |> Keyword.fetch!(PersonalConsents)
           |> Keyword.fetch!(:policy_text_version) == "personal-egress-v1"

    openai_config = Keyword.fetch!(config, OpenAI)
    assert openai_config[:endpoint] == "https://api.openai.com/v1/chat/completions"
    assert openai_config[:request_overrides] == %{store: false}

    refute Keyword.has_key?(config, RouteResolver)
    refute Keyword.has_key?(config, Storyarn.AI.TaskRegistry)
  end

  test "requires an explicit curated model when the personal lane is enabled" do
    Enum.each(@provider_model_keys, &System.delete_env/1)

    assert_raise RuntimeError, ~r/requires at least one STORYARN_AI_PERSONAL_<PROVIDER>_MODEL/, fn ->
      runtime_storyarn_config()
    end
  end

  test "a configured personal model does nothing while the lane switch is off" do
    System.put_env("STORYARN_AI_PERSONAL_BYOK_ENABLED", "false")
    config = runtime_storyarn_config()

    refute Keyword.has_key?(config, CredentialResolver)
    refute Keyword.has_key?(config, InferenceProviders)
    refute Keyword.has_key?(config, PersonalProviders)
    refute Keyword.has_key?(config, PersonalConsents)
  end

  defp runtime_storyarn_config do
    "config/runtime.exs"
    |> Config.Reader.read!(env: :dev)
    |> Keyword.fetch!(:storyarn)
  end
end
