defmodule StoryarnWeb.SettingsLive.ConnectionsTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  defp get_connections_vue(view) do
    LiveVue.Test.get_vue(view, name: "modules/account/settings/Connections")
  end

  describe "Connections LiveView" do
    setup :register_and_log_in_user

    test "renders Connections Vue component", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings/connections")
      vue = get_connections_vue(view)
      assert vue.component == "modules/account/settings/Connections"
    end

    test "passes identities prop as a list", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings/connections")
      vue = get_connections_vue(view)
      assert is_list(vue.props["identities"])
    end

    test "passes has-password prop", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings/connections")
      vue = get_connections_vue(view)
      # user_fixture creates user with password
      assert vue.props["has-password"] == true
    end

    test "starts with empty identities for fresh user", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings/connections")
      vue = get_connections_vue(view)
      assert vue.props["identities"] == []
    end
  end
end
