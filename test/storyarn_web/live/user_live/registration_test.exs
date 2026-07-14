defmodule StoryarnWeb.UserLive.RegistrationTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures

  alias Storyarn.Accounts
  alias Storyarn.Accounts.Scope
  alias Storyarn.Onboarding
  alias Storyarn.Workspaces

  defp get_registration_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/auth/registration/AuthRegistrationForm")
  end

  describe "public registration" do
    test "renders an editable registration form without an invitation", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/register")

      vue = get_registration_vue(view)

      assert vue.props["invited"] == false
      assert vue.props["login-url"] == "/users/log-in"
      assert vue.props["user-email"] == nil
      assert vue.props["form"]["errors"] == %{}
      assert has_element?(view, "#auth-layout-wrapper.min-h-screen")
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

      assert_redirect(view, "/users/log-in")

      user = Accounts.get_user_by_email_and_password(email, password)
      assert user.confirmed_at
      assert %Workspaces.Workspace{} = Workspaces.get_default_workspace(user)

      assert Enum.all?(Onboarding.summary(Scope.for_user(user)).guides, fn {_key, guide} ->
               guide.state == :pending
             end)
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
  end
end
