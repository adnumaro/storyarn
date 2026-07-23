defmodule StoryarnWeb.UserSessionController do
  use StoryarnWeb, :controller
  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Accounts
  alias Storyarn.Analytics
  alias Storyarn.RateLimiter
  alias Storyarn.Shared.TimeHelpers
  alias StoryarnWeb.ClientIp
  alias StoryarnWeb.UserAuth
  alias StoryarnWeb.UserLoginToken

  def create(conn, params) do
    if authenticated?(conn) do
      conn
      |> redirect(to: UserAuth.signed_in_path(conn))
      |> halt()
    else
      create(conn, params, dgettext("identity", "Welcome back!"))
    end
  end

  # Token-backed POST used by the LiveView login form after inline validation.
  defp create(conn, %{"user" => %{"_login_token" => login_token} = user_params}, info)
       when is_binary(login_token) and login_token != "" do
    case user_from_login_token(conn, login_token) do
      {:ok, user} ->
        conn
        |> delete_session(:login_handoff_nonce)
        |> log_in_authenticated_user(user, user_params, info)

      :error ->
        create_with_password(conn, user_params, info)
    end
  end

  defp create(conn, %{"user" => user_params}, info) do
    create_with_password(conn, user_params, info)
  end

  defp create_with_password(conn, user_params, info) do
    email = user_params["email"] || ""
    password = user_params["password"] || ""
    ip_address = ClientIp.from_conn(conn)

    case RateLimiter.check_login(ip_address) do
      :ok ->
        if user = Accounts.get_user_by_email_and_password(email, password) do
          log_in_authenticated_user(conn, user, user_params, info)
        else
          # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
          invalid_credentials_redirect(conn, user_params)
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

  defp log_in_authenticated_user(conn, user, user_params, info) do
    Analytics.identify_user(user)
    Analytics.track(user, "user logged in", %{auth_method: "password"})

    conn
    |> put_flash(:info, info)
    |> UserAuth.log_in_user(user, user_params)
  end

  defp invalid_credentials_redirect(conn, user_params) do
    email = user_params["email"] || ""

    conn
    |> put_flash(:login_error, dgettext("identity", "Invalid email or password"))
    |> put_flash(:email, String.slice(email, 0, 160))
    |> redirect(to: ~p"/users/log-in")
  end

  defp user_from_login_token(conn, token) do
    with session_nonce when is_binary(session_nonce) <- get_session(conn, :login_handoff_nonce),
         {:ok, user_id} when is_integer(user_id) <- UserLoginToken.verify(token, session_nonce),
         user when not is_nil(user) <- get_user(user_id) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  defp get_user(user_id) do
    Accounts.get_user!(user_id)
  rescue
    Ecto.NoResultsError -> nil
  end

  defp authenticated?(conn) do
    match?(%{current_scope: %{user: %Accounts.User{}}}, conn.assigns)
  end

  def confirm_access(conn, %{"sudo_handoff" => sudo_handoff, "return_to" => requested_return_to}) do
    user = conn.assigns.current_scope.user
    session_token = get_session(conn, :user_token)
    return_to = UserAuth.safe_sudo_return_to(requested_return_to) || ~p"/users/settings"

    if UserAuth.sudo_handoff_valid?(user, session_token, sudo_handoff) do
      # Rotate this browser onto a freshly authenticated session token. The
      # previous token remains un-elevated, so a browser holding a copy does
      # not inherit the password confirmation.
      updated_user = %{user | authenticated_at: TimeHelpers.now()}

      conn
      |> put_session(:user_return_to, return_to)
      |> UserAuth.log_in_user(updated_user)
    else
      conn
      |> put_flash(
        :error,
        dgettext("identity", "Your access confirmation has expired. Please try again.")
      )
      |> redirect(to: UserAuth.sudo_confirmation_path(return_to))
    end
  end

  def confirm_access(conn, params) do
    return_to =
      params
      |> Map.get("return_to")
      |> UserAuth.safe_sudo_return_to()
      |> Kernel.||(~p"/users/settings")

    conn
    |> put_flash(
      :error,
      dgettext("identity", "Your access confirmation has expired. Please try again.")
    )
    |> redirect(to: UserAuth.sudo_confirmation_path(return_to))
  end

  def update_password(conn, %{"user" => user_params} = params) do
    user = conn.assigns.current_scope.user
    session_token = get_session(conn, :user_token)
    sudo_grant = params["sudo_grant"]

    case UserAuth.authorize_sudo(user, session_token, sudo_grant) do
      {:ok, valid_grant} ->
        update_password(conn, user, user_params, valid_grant)

      :error ->
        conn
        |> put_flash(
          :error,
          dgettext("identity", "Please re-authenticate to change your password.")
        )
        |> redirect(to: UserAuth.sudo_confirmation_path(~p"/users/settings/security"))
    end
  end

  defp update_password(conn, user, user_params, valid_grant) do
    case Accounts.update_user_password(user, user_params) do
      {:ok, {updated_user, expired_tokens}} ->
        # disconnect all existing LiveViews with old sessions
        UserAuth.disconnect_sessions(expired_tokens)

        # The password was already authorized and persisted. Start the
        # replacement session directly instead of re-entering the public
        # login flow, whose IP rate limit could otherwise strand the user
        # after all of their previous sessions have been revoked.
        updated_user = %{updated_user | authenticated_at: TimeHelpers.now()}

        conn
        |> put_session(:user_return_to, ~p"/users/settings/security")
        |> put_flash(:info, dgettext("identity", "Password updated successfully!"))
        |> UserAuth.log_in_user(updated_user, user_params)

      {:error, _changeset} ->
        return_to = UserAuth.with_sudo_grant(~p"/users/settings/security", valid_grant)

        conn
        |> put_flash(:error, dgettext("identity", "Failed to update password."))
        |> redirect(to: return_to)
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, dgettext("identity", "Logged out successfully."))
    |> UserAuth.log_out_user()
  end
end
