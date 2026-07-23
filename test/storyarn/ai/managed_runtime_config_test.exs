defmodule Storyarn.AI.ManagedRuntimeConfigTest do
  use ExUnit.Case, async: false

  alias Storyarn.AI.CredentialResolver.Managed
  alias Storyarn.AI.InferenceProviders
  alias Storyarn.AI.InferenceProviders.Fireworks
  alias Storyarn.AI.InferenceProviders.Together
  alias Storyarn.AI.RouteResolver

  @managed_env %{
    "STORYARN_AI_MANAGED_ENABLED" => "true",
    "STORYARN_AI_MANAGED_ZDR_VERIFIED" => "true",
    "STORYARN_AI_MANAGED_NO_TRAINING_VERIFIED" => "true",
    "STORYARN_AI_FIREWORKS_API_KEY" => "test-fireworks-key",
    "STORYARN_AI_TOGETHER_API_KEY" => "test-together-key",
    "STORYARN_AI_MANAGED_MODEL" => "test-model",
    "STORYARN_AI_MANAGED_REGION" => "global",
    "STORYARN_AI_PROVIDER_PRICE_VERSION" => "1",
    "STORYARN_AI_PROVIDER_PRICE_CURRENCY" => "USD",
    "STORYARN_AI_PROVIDER_INPUT_PER_MILLION" => "0.1",
    "STORYARN_AI_PROVIDER_OUTPUT_PER_MILLION" => "0.2",
    "STORYARN_AI_PROVIDER_MAX_OPERATION_COST" => "0.01",
    "STORYARN_AI_PROVIDER_GLOBAL_DAILY_CAP" => "10",
    "STORYARN_AI_PROVIDER_GLOBAL_MONTHLY_CAP" => "100",
    "STORYARN_AI_PROVIDER_WORKSPACE_DAILY_CAP" => "1",
    "STORYARN_AI_DIAGNOSTIC_PRICE_ID" => "diagnostic-v1",
    "STORYARN_AI_DIAGNOSTIC_PRICE_VERSION" => "1",
    "STORYARN_AI_DIAGNOSTIC_PRICE_UNITS" => "1"
  }

  @managed_keys Map.keys(@managed_env) ++
                  [
                    "STORYARN_AI_MANAGED_PROVIDER",
                    "STORYARN_AI_FIREWORKS_ENDPOINT",
                    "STORYARN_AI_TOGETHER_ENDPOINT"
                  ]

  setup do
    original = Map.new(@managed_keys, &{&1, System.get_env(&1)})
    Enum.each(@managed_env, fn {key, value} -> System.put_env(key, value) end)

    on_exit(fn ->
      Enum.each(original, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end)
  end

  test "selects Fireworks for new routes while keeping both adapters and credentials available" do
    System.put_env("STORYARN_AI_MANAGED_PROVIDER", "fireworks")
    config = runtime_storyarn_config()

    assert managed_route(config)[:provider] == "fireworks"
    assert managed_route(config)[:credential_ref] == "storyarn-managed-fireworks-v1"
    assert managed_provider_registry(config) == %{"fireworks" => Fireworks, "together" => Together}

    assert credential_config(config)[:credentials] == %{
             "storyarn-managed-fireworks-v1" => "test-fireworks-key",
             "storyarn-managed-together-v1" => "test-together-key"
           }
  end

  test "selects Together without changing the provider registry" do
    System.put_env("STORYARN_AI_MANAGED_PROVIDER", "together")
    config = runtime_storyarn_config()

    assert managed_route(config)[:provider] == "together"
    assert managed_route(config)[:credential_ref] == "storyarn-managed-together-v1"
    assert managed_provider_registry(config) == %{"fireworks" => Fireworks, "together" => Together}
  end

  test "rejects unsupported providers and missing privacy attestations" do
    System.put_env("STORYARN_AI_MANAGED_PROVIDER", "unsupported")

    assert_raise RuntimeError, ~r/must be fireworks or together/, fn ->
      runtime_storyarn_config()
    end

    System.put_env("STORYARN_AI_MANAGED_PROVIDER", "fireworks")
    System.delete_env("STORYARN_AI_MANAGED_NO_TRAINING_VERIFIED")

    assert_raise RuntimeError, ~r/ZDR and no-training verification/, fn ->
      runtime_storyarn_config()
    end
  end

  defp runtime_storyarn_config do
    "config/runtime.exs"
    |> Config.Reader.read!(env: :dev)
    |> Keyword.fetch!(:storyarn)
  end

  defp managed_route(config) do
    config
    |> Keyword.fetch!(RouteResolver)
    |> Keyword.fetch!(:managed)
  end

  defp managed_provider_registry(config) do
    config
    |> Keyword.fetch!(InferenceProviders)
    |> Keyword.fetch!(:providers)
    |> Map.take(["fireworks", "together"])
  end

  defp credential_config(config), do: Keyword.fetch!(config, Managed)
end
