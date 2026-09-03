defmodule StoryarnWeb.SettingsLive.PreferencesTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures

  alias Storyarn.Accounts

  defp get_preferences_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/account/settings/AccountSettingsPreferences")
  end

  describe "Preferences page" do
    test "renders the page with the language options", %{conn: conn} do
      {:ok, view, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings/preferences")

      vue = get_preferences_vue(view)
      assert vue.component == "live/account/settings/AccountSettingsPreferences"
      assert vue.props["locale"] == "en"
      assert vue.props["save-status"] == "idle"

      assert vue.props["locale-options"] == [
               %{
                 "flagCode" => "gb",
                 "label" => "English",
                 "languageTag" => "en",
                 "shortLabel" => "EN",
                 "value" => "en"
               },
               %{
                 "flagCode" => "es",
                 "label" => "Español",
                 "languageTag" => "es",
                 "shortLabel" => "ES",
                 "value" => "es"
               }
             ]
    end

    test "does not require sudo mode", %{conn: conn} do
      stale_authenticated_at = DateTime.add(DateTime.utc_now(:second), -21, :minute)

      {:ok, view, _html} =
        conn
        |> log_in_user(user_fixture(), token_authenticated_at: stale_authenticated_at)
        |> live(~p"/users/settings/preferences")

      assert get_preferences_vue(view).props["locale"] == "en"
    end

    test "redirects unauthenticated users", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, ~p"/users/settings/preferences")
    end
  end

  describe "update_locale event" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "saves the language and switches the app locale", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/users/settings/preferences")

      render_click(view, "update_locale", %{"locale" => "es"})

      vue = get_preferences_vue(view)
      assert vue.props["locale"] == "es"
      assert vue.props["save-status"] == "saved"
      assert Accounts.get_user!(user.id).locale == "es"
      refute_redirected(view)
    end

    test "rejects an unknown language", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/users/settings/preferences")

      html = render_click(view, "update_locale", %{"locale" => "xx"})

      assert html =~ "Could not update the language."
      assert Accounts.get_user!(user.id).locale != "xx"
    end
  end
end
