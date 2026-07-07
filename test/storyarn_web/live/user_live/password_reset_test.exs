defmodule StoryarnWeb.UserLive.PasswordResetTest do
  use StoryarnWeb.ConnCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures

  alias Storyarn.Accounts
  alias Storyarn.Accounts.UserToken
  alias Storyarn.RateLimiter
  alias Storyarn.Repo
  alias Storyarn.Workers.DeliverResetPasswordInstructionsWorker

  defp get_forgot_password_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/auth/reset-password/AuthForgotPasswordForm")
  end

  defp get_reset_password_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/auth/reset-password/AuthResetPasswordForm")
  end

  defp get_flash_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/layouts/flash/FlashGroup")
  end

  describe "forgot password page" do
    test "renders the request form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/reset-password")

      vue = get_forgot_password_vue(view)

      assert vue.component == "live/auth/reset-password/AuthForgotPasswordForm"
      assert vue.props["login-url"] == "/users/log-in"
      assert vue.props["form"]["name"] == "password_reset"
      assert vue.props["instructions-sent"] == false
      assert vue.props["request-error"] == nil
    end

    test "validates malformed email inline", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/reset-password")

      render_change(view, "validate", %{"password_reset" => %{"email" => "not valid"}})

      vue = get_forgot_password_vue(view)
      assert vue.props["form"]["errors"]["email"] == ["must have the @ sign and no spaces"]
    end

    test "translates malformed email errors", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/reset-password?locale=es")

      render_change(view, "validate", %{"password_reset" => %{"email" => "not valid"}})

      vue = get_forgot_password_vue(view)
      assert vue.props["form"]["errors"]["email"] == ["debe incluir @ y no contener espacios"]
    end

    test "queues instructions for an existing user without disclosing account existence", %{conn: conn} do
      user = user_fixture()
      {:ok, view, _html} = live(conn, ~p"/users/reset-password")

      render_click(view, "send_instructions", %{"password_reset" => %{"email" => user.email}})

      vue = get_forgot_password_vue(view)
      flash = get_flash_vue(view)

      assert vue.props["instructions-sent"] == true
      assert vue.props["request-error"] == nil
      refute Map.get(flash.props["flash"], "info")
      assert Repo.get_by(UserToken, user_id: user.id, context: "reset_password")
      assert_enqueued(worker: DeliverResetPasswordInstructionsWorker, args: %{"email" => user.email})
      refute_receive {:email, _email}, 50
      refute_receive {:delivered_email, _email}, 50
      refute_receive {:swoosh, :delivered_email, _email}, 50

      perform_latest_reset_password_job()
      assert receive_delivered_email()
    end

    test "shows the same success message for an unknown email", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/reset-password")

      render_click(view, "send_instructions", %{"password_reset" => %{"email" => unique_user_email()}})

      vue = get_forgot_password_vue(view)
      flash = get_flash_vue(view)

      assert vue.props["instructions-sent"] == true
      assert vue.props["request-error"] == nil
      refute Map.get(flash.props["flash"], "info")
      refute Repo.get_by(UserToken, context: "reset_password")
      refute_reset_password_job_enqueued()
    end

    test "can return from confirmation to the request form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/reset-password")

      render_click(view, "send_instructions", %{"password_reset" => %{"email" => unique_user_email()}})
      assert get_forgot_password_vue(view).props["instructions-sent"] == true

      render_click(view, "reset_request_form", %{})

      vue = get_forgot_password_vue(view)
      assert vue.props["instructions-sent"] == false
      assert vue.props["request-error"] == nil
      assert vue.props["form"]["values"]["email"] in [nil, ""]
    end

    test "rate limits password reset by email", %{conn: conn} do
      original = Application.get_env(:storyarn, RateLimiter)
      Application.put_env(:storyarn, RateLimiter, enabled: true)

      email = unique_user_email()

      try do
        for _ <- 1..3 do
          {:ok, view, _html} = live(conn, ~p"/users/reset-password")

          render_click(view, "send_instructions", %{"password_reset" => %{"email" => email}})

          assert get_forgot_password_vue(view).props["instructions-sent"] == true
        end

        {:ok, view, _html} = live(conn, ~p"/users/reset-password")

        render_click(view, "send_instructions", %{"password_reset" => %{"email" => email}})

        vue = get_forgot_password_vue(view)
        flash = get_flash_vue(view)

        assert vue.props["instructions-sent"] == false
        assert vue.props["request-error"] == "Too many password reset requests. Please try again later."
        refute Map.get(flash.props["flash"], "error")
      after
        Application.put_env(:storyarn, RateLimiter, original || [])
      end
    end
  end

  describe "public auth gating" do
    setup :register_and_log_in_user

    test "redirects authenticated users away from the forgot password page", %{conn: conn} do
      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/users/reset-password")
      assert to =~ "/workspaces/"
    end

    test "redirects authenticated users away from reset token pages", %{conn: conn} do
      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/users/reset-password/any-token")
      assert to =~ "/workspaces/"
    end
  end

  describe "reset password page" do
    setup do
      user = user_fixture()

      token = extract_reset_password_token(user)

      %{user: user, token: token}
    end

    test "redirects for an invalid token", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/reset-password", flash: flash}}} =
               live(conn, ~p"/users/reset-password/oops")

      assert flash["error"] == "Invalid or expired password reset link."
    end

    test "renders the reset form for a valid token", %{conn: conn, token: token} do
      {:ok, view, _html} = live(conn, ~p"/users/reset-password/#{token}")

      vue = get_reset_password_vue(view)

      assert vue.component == "live/auth/reset-password/AuthResetPasswordForm"
      assert vue.props["login-url"] == "/users/log-in"
      assert vue.props["form"]["name"] == "user"
      assert vue.props["reset-complete"] == false
    end

    test "validates password inline", %{conn: conn, token: token} do
      {:ok, view, _html} = live(conn, ~p"/users/reset-password/#{token}")

      render_click(view, "reset_password", %{
        "user" => %{"password" => "short", "password_confirmation" => "different"}
      })

      vue = get_reset_password_vue(view)
      assert vue.props["form"]["errors"]["password"] == ["should be at least 12 character(s)"]
      assert vue.props["form"]["errors"]["password_confirmation"] == ["does not match password"]
    end

    test "translates password errors", %{conn: conn, token: token} do
      {:ok, view, _html} = live(conn, ~p"/users/reset-password/#{token}?locale=es")

      render_click(view, "reset_password", %{
        "user" => %{"password" => "short", "password_confirmation" => "different"}
      })

      vue = get_reset_password_vue(view)
      assert vue.props["form"]["errors"]["password"] == ["debería tener al menos 12 caracteres"]
      assert vue.props["form"]["errors"]["password_confirmation"] == ["no coincide con la contraseña"]
    end

    test "updates the password and renders a persistent success state", %{
      conn: conn,
      user: user,
      token: token
    } do
      {:ok, view, _html} = live(conn, ~p"/users/reset-password/#{token}")

      render_click(view, "reset_password", %{
        "user" => %{
          "password" => "new valid password",
          "password_confirmation" => "new valid password"
        }
      })

      vue = get_reset_password_vue(view)
      flash = get_flash_vue(view)

      assert vue.props["reset-complete"] == true
      refute Map.get(flash.props["flash"], "info")
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  defp extract_reset_password_token(user) do
    assert {:ok, :queued} =
             Accounts.deliver_user_reset_password_instructions(user, fn token ->
               "[TOKEN]#{token}[TOKEN]"
             end)

    perform_latest_reset_password_job()
    email = receive_delivered_email()

    [_, token | _] = String.split(email.text_body, "[TOKEN]")
    token
  end

  defp perform_latest_reset_password_job do
    job =
      Repo.one!(
        from(job in Oban.Job,
          where: job.worker == ^inspect(DeliverResetPasswordInstructionsWorker),
          order_by: [desc: job.id],
          limit: 1
        )
      )

    assert :ok = perform_job(DeliverResetPasswordInstructionsWorker, job.args)
  end

  defp refute_reset_password_job_enqueued do
    refute Repo.exists?(
             from(job in Oban.Job,
               where: job.worker == ^inspect(DeliverResetPasswordInstructionsWorker)
             )
           )
  end

  defp receive_delivered_email do
    receive do
      {:email, email} -> email
      {:delivered_email, email} -> email
      {:swoosh, :delivered_email, email} -> email
    after
      500 -> flunk("Expected reset password email to be delivered")
    end
  end
end
