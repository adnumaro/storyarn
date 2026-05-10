defmodule StoryarnWeb.SettingsLive.ProfileTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures

  defp get_profile_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/account/settings/Profile")
  end

  describe "Profile settings page" do
    test "renders profile settings page as Vue component", %{conn: conn} do
      {:ok, view, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings")

      vue = get_profile_vue(view)
      assert vue.component == "live/account/settings/Profile"
    end

    test "passes current user email to Vue", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/settings")

      vue = get_profile_vue(view)
      assert vue.props["current-email"] == user.email
    end

    test "passes profile_form and email_form props", %{conn: conn} do
      {:ok, view, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings")

      vue = get_profile_vue(view)
      assert is_map(vue.props["profile-form"])
      assert is_map(vue.props["email-form"])
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/users/settings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end
  end

  describe "update profile event" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "can update display name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      render_click(view, "update_profile", %{"user" => %{"display_name" => "New Name"}})

      {path, _flash} = assert_redirect(view)
      assert path =~ "/users/settings"
    end

    test "validates profile on change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      render_click(view, "validate_profile", %{"user" => %{"display_name" => "Test"}})

      # Should not crash and Vue component still renders
      vue = get_profile_vue(view)
      assert vue.component == "live/account/settings/Profile"
    end
  end

  describe "update email event" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "sends email change instructions", %{conn: conn} do
      new_email = unique_user_email()

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      result = render_click(view, "update_email", %{"user" => %{"email" => new_email}})

      assert result =~ "A link to confirm your email"
    end

    test "renders errors with invalid email", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      render_click(view, "validate_email", %{"user" => %{"email" => "with spaces"}})

      vue = get_profile_vue(view)
      email_form = vue.props["email-form"]
      # The form should now have errors
      assert email_form["errors"] != %{} or email_form["valid"] == false
    end

    test "renders errors when email did not change", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      result = render_click(view, "update_email", %{"user" => %{"email" => user.email}})

      assert result =~ "did not change"
    end
  end
end
