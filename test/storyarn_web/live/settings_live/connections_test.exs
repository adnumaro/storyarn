defmodule StoryarnWeb.SettingsLive.ConnectionsTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "Connections LiveView" do
    setup :register_and_log_in_user

    test "renders page title", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/users/settings/connections")
      assert html =~ "Connected Accounts"
    end

    test "renders subtitle", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/users/settings/connections")
      assert html =~ "Link your social accounts"
    end

    test "renders all three providers", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/users/settings/connections")
      assert html =~ "GitHub"
      assert html =~ "Google"
      assert html =~ "Discord"
    end

    test "shows Not connected for providers without identity", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/users/settings/connections")
      assert html =~ "Not connected"
    end

    test "shows Connect button for unlinked providers", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/users/settings/connections")
      assert html =~ "Connect"
      assert html =~ "/auth/github/link"
      assert html =~ "/auth/google/link"
      assert html =~ "/auth/discord/link"
    end

    test "renders why connect section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/users/settings/connections")
      assert html =~ "Why connect accounts?"
      assert html =~ "Sign in faster"
      assert html =~ "forget your password"
      assert html =~ "multiple authentication"
    end

    test "renders provider icons", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/users/settings/connections")
      # GitHub SVG path
      assert html =~ "M12 0c-6.626"
      # Google SVG
      assert html =~ "#4285F4"
      # Discord SVG
      assert html =~ "#5865F2"
    end

    test "sets correct current path assign", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/users/settings/connections")
      # The settings layout highlights the current nav item
      assert html =~ "connections"
    end
  end
end
