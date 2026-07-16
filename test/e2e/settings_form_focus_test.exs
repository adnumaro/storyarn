defmodule StoryarnWeb.E2E.SettingsFormFocusTest do
  @moduledoc """
  Browser coverage for preserving settings form DOM state across live validation.

  Run with: mix test.e2e test/e2e/settings_form_focus_test.exs
  """

  use PhoenixTest.Playwright.Case, async: false

  import Storyarn.AccountsFixtures
  import StoryarnWeb.E2EHelpers

  @moduletag :e2e

  test "profile validation preserves the focused input node", %{conn: conn} do
    display_name = String.duplicate("a", 101)

    conn
    |> authenticate(user_fixture())
    |> visit("/users/settings")
    |> assert_has("body .phx-connected")
    |> assert_has("#profile-display-name")
    |> evaluate(remember_input_expression("#profile-display-name"))
    |> type("#profile-display-name", display_name)
    |> assert_has("#profile-display-name[aria-invalid='true']")
    |> evaluate(focus_state_expression("#profile-display-name"), fn state ->
      assert_focus_preserved(state, "profile-display-name", display_name)
    end)
  end

  test "security validation preserves the focused input node", %{conn: conn} do
    conn
    |> authenticate(user_fixture())
    |> visit("/users/settings/security")
    |> assert_has("body .phx-connected")
    |> assert_has("#security-password")
    |> evaluate(remember_input_expression("#security-password"))
    |> type("#security-password", "abc")
    |> assert_has("#security-password[aria-invalid='true']")
    |> evaluate(focus_state_expression("#security-password"), fn state ->
      assert_focus_preserved(state, "security-password", "abc")
    end)
  end

  defp remember_input_expression(selector) do
    "window.__settingsFocusProbe = document.querySelector(#{Jason.encode!(selector)})"
  end

  defp focus_state_expression(selector) do
    """
    (() => {
      const current = document.querySelector(#{Jason.encode!(selector)});

      return {
        activeId: document.activeElement?.id ?? null,
        connected: window.__settingsFocusProbe?.isConnected ?? false,
        sameNode: current === window.__settingsFocusProbe,
        value: current?.value ?? null
      };
    })()
    """
  end

  defp assert_focus_preserved(state, input_id, value) do
    assert state == %{
             "activeId" => input_id,
             "connected" => true,
             "sameNode" => true,
             "value" => value
           }
  end
end
