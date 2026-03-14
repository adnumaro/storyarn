defmodule StoryarnWeb.UserSessionController do
  use StoryarnWeb, :controller
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Accounts
  alias Storyarn.RateLimiter
  alias StoryarnWeb.UserAuth

  def create(conn, %{"_action" => "confirmed"} = params) do
    create(conn, params, dgettext("identity", "User confirmed successfully."))
  end

  def create(conn, params) do
    create(conn, params, dgettext("identity", "Welcome back!"))
  end

  # magic link login
  defp create(conn, %{"user" => %{"token" => token} = user_params}, info) do
    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, tokens_to_disconnect}} ->
        UserAuth.disconnect_sessions(tokens_to_disconnect)

        conn
        |> put_flash(:info, info)
        |> UserAuth.log_in_user(user, user_params)

      _ ->
        conn
        |> put_flash(:error, dgettext("identity", "The link is invalid or it has expired."))
        |> redirect(to: ~p"/users/log-in")
    end
  end

  # email + password login
  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params
    ip_address = format_remote_ip(conn)

    case RateLimiter.check_login(ip_address) do
      :ok ->
        if user = Accounts.get_user_by_email_and_password(email, password) do
          conn
          |> put_flash(:info, info)
          |> UserAuth.log_in_user(user, user_params)
        else
          # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
          conn
          |> put_flash(:error, dgettext("identity", "Invalid email or password"))
          |> put_flash(:email, String.slice(email, 0, 160))
          |> redirect(to: ~p"/users/log-in")
        end

      {:error, :rate_limited} ->
        conn
        |> put_flash(
          :error,
          dgettext("identity", "Too many login attempts. Please try again later.")
        )
        |> redirect(to: ~p"/users/log-in")
    end
  end

  defp format_remote_ip(conn) do
    conn.remote_ip |> :inet.ntoa() |> to_string()
  end

  def update_password(conn, %{"user" => user_params} = params) do
    user = conn.assigns.current_scope.user

    if Accounts.sudo_mode?(user) do
      case Accounts.update_user_password(user, user_params) do
        {:ok, {_user, expired_tokens}} ->
          # disconnect all existing LiveViews with old sessions
          UserAuth.disconnect_sessions(expired_tokens)

          conn
          |> put_session(:user_return_to, ~p"/users/settings/security")
          |> create(params, dgettext("identity", "Password updated successfully!"))

        {:error, changeset} ->
          conn
          |> put_flash(:error, dgettext("identity", "Failed to update password."))
          |> render(:new, changeset: changeset)
      end
    else
      conn
      |> put_flash(
        :error,
        dgettext("identity", "Please re-authenticate to change your password.")
      )
      |> redirect(to: ~p"/users/settings/security")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, dgettext("identity", "Logged out successfully."))
    |> UserAuth.log_out_user()
  end
end
