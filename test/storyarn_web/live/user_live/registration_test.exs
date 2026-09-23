defmodule StoryarnWeb.UserLive.RegistrationTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures

  alias Storyarn.Accounts
  alias Storyarn.Accounts.Scope
  alias Storyarn.Platform.Onboarding
  alias Storyarn.Workspaces

  defp get_registration_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/auth/registration/AuthRegistrationForm")
  end

  describe "public registration" do
    test "renders an editable registration form without an invitation", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/register")

      vue = get_registration_vue(view)

      assert vue.props["invited"] == false
      assert vue.props["login-url"] == "/users/log-in?locale=en"
      assert vue.props["login-action"] == "/users/log-in?locale=en"
      assert vue.props["user-email"] == nil
      assert vue.props["form"]["errors"] == %{}
      assert vue.props["trigger-submit"] == false
      refute vue.props["login-token"]
      assert has_element?(view, "#auth-layout-wrapper.min-h-screen")

      layout = LiveVue.Test.get_vue(view, name: "live/layouts/auth/Layout")
      assert layout.props["home-url"] == "/"
    end

    test "creates a confirmed password user and default workspace", %{conn: conn} do
      email = unique_user_email()
      password = valid_user_password()
      {:ok, view, _html} = live(conn, ~p"/users/register")

      render_click(view, "save", %{
        "user" => %{
          "email" => email,
          "password" => password,
          "password_confirmation" => password
        }
      })

      vue = get_registration_vue(view)
      assert vue.props["trigger-submit"] == true
      assert is_binary(vue.props["login-token"])

      user = Accounts.get_user_by_email_and_password(email, password)
      assert user.confirmed_at
      assert %Workspaces.Workspace{} = Workspaces.get_default_workspace(user)

      assert Enum.all?(Onboarding.summary(Scope.for_user(user)).guides, fn {_key, guide} ->
               guide.state == :pending
             end)
    end

    test "signs the new account in and lands on its workspace", %{conn: conn} do
      email = unique_user_email()
      password = valid_user_password()

      {_registration, conn} =
        register_through_session_handoff(conn, ~p"/users/register", %{
          "email" => email,
          "password" => password,
          "password_confirmation" => password
        })

      user = Accounts.get_user_by_email(email)
      workspace = Workspaces.get_default_workspace(user)

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == "/workspaces/#{workspace.slug}"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Account created successfully! Welcome."
    end

    test "does not start a session from another browser", %{conn: conn} do
      email = unique_user_email()
      password = valid_user_password()
      {:ok, view, _html} = live(conn, ~p"/users/register")

      render_click(view, "save", %{
        "user" => %{
          "email" => email,
          "password" => password,
          "password_confirmation" => password
        }
      })

      login_token = get_registration_vue(view).props["login-token"]
      assert is_binary(login_token)

      conn =
        post(build_conn(), ~p"/users/log-in", %{
          "user" => %{"_login_token" => login_token, "email" => email}
        })

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Your account was created. Log in to continue."
      assert Phoenix.Flash.get(conn.assigns.flash, :email) == email
      refute Phoenix.Flash.get(conn.assigns.flash, :login_error)
    end

    test "keeps an explicit Spanish handoff", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/register?locale=es")

      vue = get_registration_vue(view)
      assert vue.props["login-url"] == "/users/log-in?locale=es"
      assert vue.props["login-action"] == "/users/log-in?locale=es"

      layout = LiveVue.Test.get_vue(view, name: "live/layouts/auth/Layout")
      assert layout.props["home-url"] == "/es"
    end

    test "returns an invalid Spanish invitation to the Spanish landing", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/es", flash: flash}}} =
               live(conn, ~p"/users/register/invalid-token?locale=es")

      assert flash["error"] =~ "El enlace de registro no es válido o ha caducado."
    end

    test "keeps validation errors in the public form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/register")

      render_click(view, "validate", %{
        "user" => %{
          "email" => "not-an-email",
          "password" => "short",
          "password_confirmation" => "different"
        }
      })

      form = get_registration_vue(view).props["form"]
      assert form["errors"]["email"]
      assert form["errors"]["password"]
    end

    test "validates bcrypt's byte limit before submit", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/register")
      password = String.duplicate("😀", 19)

      render_click(view, "validate", %{
        "user" => %{
          "email" => unique_user_email(),
          "password" => password,
          "password_confirmation" => password
        }
      })

      assert get_registration_vue(view).props["form"]["errors"]["password"]
    end
  end

  describe "invited registration" do
    test "keeps invitation email read-only", %{conn: conn} do
      email = unique_user_email()
      {:ok, {:registration_required, token}} = Accounts.prepare_invitation_user(email)

      {:ok, view, _html} = live(conn, ~p"/users/register/#{token}")
      vue = get_registration_vue(view)

      assert vue.props["invited"] == true
      assert vue.props["user-email"] == email
    end

    test "signs the invitee in and returns to the invitation", %{conn: conn} do
      email = unique_user_email()
      {:ok, {:registration_required, token}} = Accounts.prepare_invitation_user(email)
      return_to = "/workspaces/invitations/some-token"

      {_registration, conn} =
        register_through_session_handoff(
          conn,
          ~p"/users/register/#{token}?#{[return_to: return_to]}",
          %{"password" => valid_user_password()}
        )

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == return_to
    end

    test "ignores a return path that leaves the site", %{conn: conn} do
      email = unique_user_email()
      {:ok, {:registration_required, token}} = Accounts.prepare_invitation_user(email)

      {_registration, conn} =
        register_through_session_handoff(
          conn,
          ~p"/users/register/#{token}?#{[return_to: "https://evil.example/phish"]}",
          %{"password" => valid_user_password()}
        )

      user = Accounts.get_user_by_email(email)

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == "/workspaces/#{Workspaces.get_default_workspace(user).slug}"
    end
  end
end
