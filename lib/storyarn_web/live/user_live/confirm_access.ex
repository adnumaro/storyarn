defmodule StoryarnWeb.UserLive.ConfirmAccess do
  @moduledoc """
  Dedicated "Confirm Access" page for sudo mode re-authentication.

  Shown when a user tries to access sensitive settings (profile, security,
  connections) and their session has expired the sudo mode window.

  Similar to GitHub's "Confirm access" page — a simplified re-auth flow
  with clear explanation of why it's needed.
  """

  use StoryarnWeb, :live_view

  alias Storyarn.Accounts
  alias Storyarn.RateLimiter

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash} current_scope={@current_scope}>
      <.vue
        v-component="pages/auth/confirm-access"
        v-socket={@socket}
        id="confirm-access-vue"
        email={@form.params["email"] || ""}
        login-action={~p"/users/log-in"}
        back-url={~p"/workspaces"}
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
      form = to_form(%{"email" => user.email}, as: "user")
      {:ok, assign(socket, form: form)}
    end
  end

  @impl true
  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    case RateLimiter.check_magic_link(email) do
      :ok ->
        if user = Accounts.get_user_by_email(email) do
          Accounts.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}")
          )
        end

        info =
          dgettext(
            "identity",
            "If your email is in our system, you will receive a verification link shortly."
          )

        {:noreply,
         socket
         |> put_flash(:info, info)
         |> push_navigate(to: ~p"/users/confirm-access")}

      {:error, :rate_limited} ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("identity", "Too many requests. Please try again later."))
         |> push_navigate(to: ~p"/users/confirm-access")}
    end
  end
end
