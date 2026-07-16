defmodule StoryarnWeb.UserLive.ConfirmAccess do
  @moduledoc """
  Dedicated "Confirm Access" page for sudo mode re-authentication.

  Shown when a user tries to access sensitive settings (profile, security,
  connections) and their session has expired the sudo mode window.

  Asks the user to re-enter their password and issues a short-lived signed
  grant bound to the current user and session. The underlying session token is
  not elevated, so another browser holding a copy does not inherit sudo access.
  """

  use StoryarnWeb, :live_view

  alias Storyarn.Accounts
  alias Storyarn.RateLimiter
  alias StoryarnWeb.ClientIp
  alias StoryarnWeb.UserAuth

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :seo_metadata, Layouts.live_seo_metadata(assigns))

    ~H"""
    <StoryarnWeb.Components.AuthLayout.auth
      flash={@flash}
      current_scope={@current_scope}
      socket={@socket}
      seo_metadata={@seo_metadata}
    >
      <.vue
        v-component="live/auth/confirm-access/AuthConfirmAccessForm"
        v-socket={@socket}
        v-inject="auth-layout"
        id="confirm-access-vue"
        email={@email}
        back-url={@back_url}
      />
    </StoryarnWeb.Components.AuthLayout.auth>
    """
  end

  @impl true
  def mount(params, session, socket) do
    user = socket.assigns.current_scope && socket.assigns.current_scope.user
    return_to = UserAuth.safe_sudo_return_to(params["return_to"]) || ~p"/users/settings"

    if is_nil(user) do
      {:ok,
       socket
       |> put_flash(:error, dgettext("identity", "You must log in to access this page."))
       |> redirect(to: ~p"/users/log-in")}
    else
      {:ok,
       assign(socket,
         email: user.email,
         return_to: return_to,
         back_url: UserAuth.signed_in_path(user),
         session_token: session["user_token"],
         client_ip: ClientIp.from_socket(socket)
       )}
    end
  end

  @impl true
  def handle_event("confirm_access", %{"password" => password}, socket) when is_binary(password) do
    user_id = socket.assigns.current_scope.user.id

    case RateLimiter.check_sudo(user_id, socket.assigns.client_ip) do
      :ok -> reauthenticate(socket, password)
      {:error, :rate_limited} -> reply_error(socket, "rate_limited")
    end
  end

  def handle_event("confirm_access", _params, socket) do
    reply_error(socket, "invalid_password")
  end

  defp reauthenticate(socket, password) do
    case Accounts.reauthenticate_user_session(
           socket.assigns.current_scope,
           socket.assigns.session_token,
           password
         ) do
      {:ok, user} ->
        sudo_grant = UserAuth.issue_sudo_grant(user, socket.assigns.session_token)
        return_to = UserAuth.with_sudo_grant(socket.assigns.return_to, sudo_grant)

        {:noreply, push_navigate(socket, to: return_to, replace: true)}

      {:error, :invalid_credentials} ->
        reply_error(socket, "invalid_password")

      {:error, :invalid_session} ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("identity", "Your session has expired. Please log in again."))
         |> redirect(to: ~p"/users/log-in")}
    end
  end

  defp reply_error(socket, error), do: {:reply, %{ok: false, error: error}, socket}
end
