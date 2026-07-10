defmodule StoryarnWeb.SettingsLive.TutorialsTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures

  defp get_tutorials_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/account/settings/AccountSettingsTutorials")
  end

  test "renders all account-level tutorial states", %{conn: conn} do
    {:ok, view, _html} =
      conn
      |> log_in_user(user_fixture())
      |> live(~p"/users/settings/tutorials")

    vue = get_tutorials_vue(view)

    assert vue.component == "live/account/settings/AccountSettingsTutorials"

    assert Enum.map(vue.props["tutorials"], & &1["key"]) ==
             ~w(workspace sheets flows scenes localization export)

    assert Enum.all?(vue.props["tutorials"], &(&1["state"] == "inactive"))
  end

  test "restarts a single tutorial", %{conn: conn} do
    {:ok, view, _html} =
      conn
      |> log_in_user(user_fixture())
      |> live(~p"/users/settings/tutorials")

    render_click(view, "restart_tutorial", %{"tutorial" => "flows"})

    tutorials = get_tutorials_vue(view).props["tutorials"]
    assert Enum.find(tutorials, &(&1["key"] == "flows"))["state"] == "pending"
    assert Enum.find(tutorials, &(&1["key"] == "sheets"))["state"] == "inactive"
  end

  test "restarts every tutorial", %{conn: conn} do
    {:ok, view, _html} =
      conn
      |> log_in_user(user_fixture())
      |> live(~p"/users/settings/tutorials")

    render_click(view, "restart_all_tutorials", %{})

    assert Enum.all?(get_tutorials_vue(view).props["tutorials"], &(&1["state"] == "pending"))
  end

  test "redirects unauthenticated users", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} =
             live(conn, ~p"/users/settings/tutorials")
  end
end
