defmodule Storyarn.TestRuntimeConfigTest do
  use ExUnit.Case, async: false

  setup do
    original = Map.new(~w(STORYARN_E2E_TESTS PHX_SERVER), &{&1, System.get_env(&1)})
    System.delete_env("PHX_SERVER")

    on_exit(fn ->
      Enum.each(original, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end)
  end

  test "the test manifest is runtime configuration and does not invalidate compiled modules" do
    config = Config.Reader.read!("config/config.exs", env: :test)

    refute config |> Keyword.fetch!(:storyarn) |> Keyword.has_key?(:vite_manifest)
  end

  test "ordinary tests use an inert manifest and do not start the application HTTP listener" do
    System.put_env("STORYARN_E2E_TESTS", "false")
    config = test_runtime_config()

    refute config |> Keyword.fetch!(StoryarnWeb.Endpoint) |> Keyword.fetch!(:server)
    assert config |> Keyword.fetch!(:vite_manifest) |> Jason.decode!() |> Map.has_key?("assets/js/app.js")
  end

  test "browser mode survives runtime config loading and selects the real asset build" do
    System.put_env("STORYARN_E2E_TESTS", "true")
    config = test_runtime_config()

    assert config |> Keyword.fetch!(StoryarnWeb.Endpoint) |> Keyword.fetch!(:server)
    assert Keyword.fetch!(config, :vite_manifest) == {:storyarn, "priv/static/.vite/manifest.json"}
  end

  defp test_runtime_config do
    "config/test.exs"
    |> Config.Reader.read!(env: :test)
    |> Config.Reader.merge(Config.Reader.read!("config/runtime.exs", env: :test))
    |> Keyword.fetch!(:storyarn)
  end
end
