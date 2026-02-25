defmodule StoryarnWeb.SettingsLive.ProfileTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures

  describe "Profile settings page" do
    test "renders profile settings page", %{conn: conn} do
      {:ok, _view, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings")

      assert html =~ "Profile"
      assert html =~ "Personal Information"
      assert html =~ "Email Address"
    end

    test "shows user's current email", %{conn: conn} do
      user = user_fixture()

      {:ok, _view, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/settings")

      assert html =~ user.email
    end

    test "shows display name form", %{conn: conn} do
      {:ok, view, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings")

      assert html =~ "Display Name"
      assert html =~ "Save Profile"
      assert has_element?(view, "#profile_form")
    end

    test "shows email change form", %{conn: conn} do
      {:ok, view, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings")

      assert html =~ "Change Email"
      assert has_element?(view, "#email_form")
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/users/settings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end
  end

  describe "update profile form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "can update display name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      result =
        view
        |> form("#profile_form", %{"user" => %{"display_name" => "New Name"}})
        |> render_submit()

      assert result =~ "Profile updated successfully"
    end

    test "validates profile on change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      # Trigger validation via phx-change
      view
      |> element("#profile_form")
      |> render_change(%{"user" => %{"display_name" => "Test"}})

      # Should not crash and form stays rendered
      assert has_element?(view, "#profile_form")
    end
  end

  describe "update email form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "sends email change instructions", %{conn: conn} do
      new_email = unique_user_email()

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      result =
        view
        |> form("#email_form", %{"user" => %{"email" => new_email}})
        |> render_submit()

      assert result =~ "A link to confirm your email"
    end

    test "renders errors with invalid email", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      result =
        view
        |> element("#email_form")
        |> render_change(%{
          "user" => %{"email" => "with spaces"}
        })

      assert result =~ "must have the @ sign and no spaces"
    end

    test "renders errors when email did not change", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      result =
        view
        |> form("#email_form", %{"user" => %{"email" => user.email}})
        |> render_submit()

      assert result =~ "did not change"
    end
  end
end
