defmodule StoryarnWeb.UserLive.Registration do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias Storyarn.Accounts
  alias Storyarn.RateLimiter

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash} current_scope={@current_scope}>
      <.vue
        v-component="modules/auth/SignUp"
        v-socket={@socket}
        id="registration-vue"
        form={@form}
        user-email={@invited_user.email}
        login-url={~p"/users/log-in"}
      />
    </Layouts.auth>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: StoryarnWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(%{"token" => token}, _session, socket) do
    ip =
      case get_connect_info(socket, :peer_data) do
        %{address: addr} when is_tuple(addr) -> addr |> :inet.ntoa() |> to_string()
        _ -> "unknown"
      end

    case Accounts.get_user_by_invite_token(token) do
      {user, token_record} ->
        # We start with an empty changeset (casted so params is %{}) so no validation errors are shown on load
        changeset = Ecto.Changeset.cast(user, %{}, [])

        {:ok,
         socket
         |> assign(:invited_user, user)
         |> assign(:invite_token, token_record)
         |> assign(:client_ip, ip)
         |> assign_form(changeset)}

      nil ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("identity", "Invalid or expired registration link."))
         |> redirect(to: ~p"/")}
    end
  end

  def mount(_params, _session, socket) do
    {:ok, redirect(socket, to: ~p"/")}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case RateLimiter.check_registration(socket.assigns[:client_ip] || "unknown") do
      :ok ->
        do_register(socket, user_params)

      {:error, :rate_limited} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           dgettext("identity", "Too many registration attempts. Please try again later.")
         )
         |> push_navigate(to: ~p"/")}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    user = socket.assigns.invited_user
    changeset = Accounts.change_user_password(user, user_params, hash_password: false)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  # Private helpers

  defp do_register(socket, user_params) do
    user = socket.assigns.invited_user
    token_record = socket.assigns.invite_token

    case Accounts.complete_registration(user, token_record, user_params) do
      {:ok, _updated_user} ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("identity", "Account created successfully! Welcome."))
         # We cannot call typical redirect, log_in_user from socket. It's best to redirect to a POST endpoint 
         # or use the standard log_in_user hook if we can. Wait, UserAuth has `log_in_user` for controllers.
         # For LiveViews, `push_navigate` but the cookies must be set.
         # Standard phx.gen.auth redirects to login page with flash or handles it in `UserSessionController.create/2`.
         # Let's redirect to `/users/log-in` with success message for now, forcing them to login immediately:
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
