defmodule StoryarnWeb.Live.Shared.SudoReauth do
  @moduledoc """
  In-place re-authentication for settings pages mounted with
  `{StoryarnWeb.UserAuth, :load_sudo_state}`.

  While `sudo_active` is false the page renders its sensitive sections locked
  and shows a banner asking for the password. Confirming issues the same signed
  handoff as the dedicated confirm-access page; the client exchanges it through
  the authenticated POST to `/users/confirm-access`, which rotates the session
  and returns to the page with sudo mode active.
  """

  use Gettext, backend: Storyarn.Gettext
  use StoryarnWeb, :verified_routes

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, redirect: 2]

  alias Storyarn.Accounts
  alias StoryarnWeb.ClientIp
  alias StoryarnWeb.UserAuth

  @doc """
  Assigns what the re-authentication banner needs. Call from `mount/3` with
  the path the browser should return to once the session is rotated.
  """
  def assign_reauth(socket, return_to) do
    assign(socket,
      client_ip: ClientIp.from_socket(socket),
      sudo_handoff: nil,
      trigger_sudo_submit: false,
      sudo_return_to: UserAuth.safe_sudo_return_to(return_to) || "/users/settings"
    )
  end

  @doc """
  The banner's `state` prop: where the hidden form posts, the CSRF token, the
  return path and the pending handoff. Pass the three assigns explicitly so
  HEEx keeps tracking them.
  """
  def reauth_props(return_to, sudo_handoff, trigger_submit) do
    %{
      confirmAction: ~p"/users/confirm-access",
      csrfToken: Plug.CSRFProtection.get_csrf_token(),
      returnTo: return_to,
      sudoHandoff: sudo_handoff,
      triggerSubmit: trigger_submit
    }
  end

  @doc """
  Handles the banner's `confirm_access` event. Replies with an error code the
  banner can translate, or assigns the handoff the client submits.
  """
  def confirm(socket, %{"password" => password}) when is_binary(password) do
    user_id = socket.assigns.current_scope.user.id

    case Accounts.check_sudo_rate(user_id, socket.assigns.client_ip) do
      :ok -> reauthenticate(socket, password)
      {:error, :rate_limited} -> reply_error(socket, "rate_limited")
    end
  end

  def confirm(socket, _params), do: reply_error(socket, "invalid_password")

  @doc """
  Runs `fun` when the session is still inside the sudo window; otherwise locks
  the page again instead of navigating away.
  """
  def with_sudo(socket, fun) when is_function(fun, 1) do
    case UserAuth.authorize_sudo(
           socket.assigns.current_scope.user,
           socket.assigns.sudo_session_token,
           socket.assigns.sudo_grant
         ) do
      {:ok, _grant} ->
        fun.(socket)

      :error ->
        {:noreply,
         socket
         |> assign(:sudo_active, false)
         |> put_flash(:error, dgettext("settings", "Confirm it's you to change these settings."))}
    end
  end

  defp reauthenticate(socket, password) do
    case Accounts.reauthenticate_user_session(
           socket.assigns.current_scope,
           socket.assigns.sudo_session_token,
           password
         ) do
      {:ok, user} ->
        handoff = UserAuth.issue_sudo_handoff(user, socket.assigns.sudo_session_token)
        {:noreply, assign(socket, sudo_handoff: handoff, trigger_sudo_submit: true)}

      {:error, :invalid_credentials} ->
        reply_error(socket, "invalid_password")

      {:error, :invalid_session} ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("identity", "Your session has expired. Please log in again."))
         |> redirect(to: "/users/log-in")}
    end
  end

  defp reply_error(socket, error) do
    {:reply, %{ok: false, error: error}, assign(socket, sudo_handoff: nil, trigger_sudo_submit: false)}
  end
end
