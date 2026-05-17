defmodule Storyarn.AnalyticsTest do
  use ExUnit.Case, async: false

  alias Storyarn.Accounts.User
  alias Storyarn.Analytics

  @posthog_keys [:enable, :api_key, :api_host, :enable_error_tracking, :in_app_otp_apps, :test_mode]

  defmodule TestAdapter do
    @moduledoc false
    def capture(payload) do
      send(Process.get(:analytics_test_pid), {:analytics_capture, payload})
      :ok
    end

    def identify(payload) do
      send(Process.get(:analytics_test_pid), {:analytics_identify, payload})
      :ok
    end
  end

  setup do
    original_adapter = Application.get_env(:storyarn, :analytics_adapter)
    original_posthog = snapshot_posthog_env()
    original_posthog_frontend = Application.get_env(:storyarn, :posthog_frontend)

    Process.put(:analytics_test_pid, self())
    Application.put_env(:storyarn, :analytics_adapter, TestAdapter)

    on_exit(fn ->
      restore_storyarn_env(:analytics_adapter, original_adapter)
      restore_posthog_env(original_posthog)
      restore_storyarn_env(:posthog_frontend, original_posthog_frontend)
      Process.delete(:analytics_test_pid)
    end)
  end

  test "track sends sanitized allowlisted properties" do
    user = %User{id: 42}

    Analytics.track(user, "project created", %{
      auth_method: "password",
      project_id: 7,
      workspace_id: 3,
      name: "Private project",
      slug: "private-project",
      email: "owner@example.com",
      nested: %{private: true}
    })

    assert_receive {:analytics_capture,
                    %{
                      event: "project created",
                      distinct_id: "user:42",
                      properties: %{"project_id" => 7, "workspace_id" => 3}
                    }}
  end

  test "track ignores unknown event names" do
    Analytics.track(%User{id: 42}, "custom free form event", %{project_id: 7})

    refute_receive {:analytics_capture, _payload}
  end

  test "identify_user excludes email and display name" do
    user = %User{
      id: 42,
      email: "owner@example.com",
      display_name: "Private Owner",
      is_super_admin: true,
      locale: "es"
    }

    Analytics.identify_user(user, %{email: "owner@example.com", locale: "en"})

    assert_receive {:analytics_identify,
                    %{
                      distinct_id: "user:42",
                      properties: %{"is_super_admin" => true, "locale" => "en"}
                    }}
  end

  test "frontend_config returns nil when frontend analytics is disabled" do
    put_posthog_env(
      enable: true,
      api_key: "phc_test",
      api_host: "https://us.i.posthog.com"
    )

    Application.put_env(:storyarn, :posthog_frontend, frontend_enabled: false)

    refute Analytics.frontend_config(%User{id: 42})
  end

  test "frontend_config exposes only safe user context" do
    put_posthog_env(
      enable: true,
      api_key: "phc_test",
      api_host: "https://us.i.posthog.com/"
    )

    Application.put_env(:storyarn, :posthog_frontend,
      frontend_enabled: true,
      error_tracking_enabled: false
    )

    assert Analytics.frontend_config(%User{
             id: 42,
             email: "owner@example.com",
             display_name: "Private Owner",
             is_super_admin: false,
             locale: "es"
           }) == %{
             api_key: "phc_test",
             distinct_id: "user:42",
             error_tracking_enabled: false,
             host: "https://us.i.posthog.com",
             user_locale: "es",
             user_super_admin: false
           }
  end

  test "frontend_config exposes error tracking flag without changing identity data" do
    put_posthog_env(
      enable: true,
      api_key: "phc_test",
      api_host: "https://us.i.posthog.com"
    )

    Application.put_env(:storyarn, :posthog_frontend,
      frontend_enabled: true,
      error_tracking_enabled: true
    )

    assert %{
             distinct_id: "user:42",
             error_tracking_enabled: true,
             user_locale: "es"
           } =
             Analytics.frontend_config(%User{
               id: 42,
               email: "owner@example.com",
               display_name: "Private Owner",
               locale: "es"
             })
  end

  defp restore_storyarn_env(key, nil), do: Application.delete_env(:storyarn, key)
  defp restore_storyarn_env(key, value), do: Application.put_env(:storyarn, key, value)

  defp put_posthog_env(config) do
    Enum.each(config, fn {key, value} ->
      Application.put_env(:posthog, key, value)
    end)
  end

  defp snapshot_posthog_env do
    Map.new(@posthog_keys, fn key -> {key, Application.fetch_env(:posthog, key)} end)
  end

  defp restore_posthog_env(snapshot) do
    Enum.each(snapshot, fn
      {key, {:ok, value}} -> Application.put_env(:posthog, key, value)
      {key, :error} -> Application.delete_env(:posthog, key)
    end)
  end
end
