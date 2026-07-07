defmodule StoryarnWeb.UserSessionController do
  use StoryarnWeb, :controller
  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Accounts
  alias Storyarn.Analytics
  alias Storyarn.RateLimiter
  alias StoryarnWeb.ClientIp
  alias StoryarnWeb.UserAuth
  alias StoryarnWeb.UserLoginToken

  def create(conn, %{"_action" => "confirmed", "user" => user_params} = params) do
    params =
      put_in(
        params,
        ["user", "email"],
        confirmed_access_email(conn, user_params)
      )

    create(conn, params, dgettext("identity", "User confirmed successfully."))
  end

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
    case user_from_login_token(login_token) do
      {:ok, user} ->
        log_in_authenticated_user(conn, user, user_params, info)

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

  defp user_from_login_token(token) do
    with {:ok, user_id} when is_integer(user_id) <- UserLoginToken.verify(token),
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

  defp confirmed_access_email(conn, user_params) do
    case user_params["email"] do
      email when is_binary(email) and email != "" ->
        email

      _ ->
        get_in(conn.assigns, [:current_scope, Access.key(:user), Access.key(:email)]) || ""
    end
  end

  defp authenticated?(conn) do
    match?(%{current_scope: %{user: %Accounts.User{}}}, conn.assigns)
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
