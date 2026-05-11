defmodule StoryarnWeb.UserLive.ConfirmAccess do
  @moduledoc """
  Dedicated "Confirm Access" page for sudo mode re-authentication.

  Shown when a user tries to access sensitive settings (profile, security,
  connections) and their session has expired the sudo mode window.

  Asks the user to re-enter their password to refresh `authenticated_at`
  on their session token.
  """

  use StoryarnWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash} current_scope={@current_scope} socket={@socket}>
      <.vue
        v-component="live/auth/confirm-access/Form"
        v-socket={@socket}
        v-inject="auth-layout"
        id="confirm-access-vue"
        email={@email}
        login-action={~p"/users/log-in"}
        back-url={~p"/workspaces"}
        csrf-token={Plug.CSRFProtection.get_csrf_token()}
      />
    </Layouts.auth>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope && socket.assigns.current_scope.user

    if is_nil(user) do
      {:ok,
       socket
       |> put_flash(:error, dgettext("identity", "You must log in to access this page."))
       |> redirect(to: ~p"/users/log-in")}
    else
      {:ok, assign(socket, email: user.email)}
    end
  end
end
