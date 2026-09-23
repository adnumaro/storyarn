defmodule StoryarnWeb.UserLive.Registration do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias Storyarn.Accounts
  alias StoryarnWeb.ClientIp
  alias StoryarnWeb.PublicURLs
  alias StoryarnWeb.UserLoginToken

  on_mount {StoryarnWeb.UserAuth, :redirect_if_user_is_authenticated}

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
        v-component="live/auth/registration/AuthRegistrationForm"
        v-socket={@socket}
        v-inject="auth-layout"
        id="registration-vue"
        form={@form}
        user-email={@registration_user.email}
        invited={!!@invite_token}
        login-url={PublicURLs.locale_handoff_path(~p"/users/log-in", @locale)}
        trigger-submit={@trigger_submit}
        login-token={@login_token}
        csrf-token={Plug.CSRFProtection.get_csrf_token()}
        login-action={PublicURLs.locale_handoff_path(~p"/users/log-in", @locale)}
      />
    </StoryarnWeb.Components.AuthLayout.auth>
    """
  end

  @impl true
  def mount(%{"token" => token} = params, session, socket) do
    case Accounts.get_user_by_invite_token(token) do
      {user, token_record} ->
        # We start with an empty changeset (casted so params is %{}) so no validation errors are shown on load
        changeset = Ecto.Changeset.cast(user, %{}, [])

        {:ok,
         socket
         |> assign(:registration_user, user)
         |> assign(:invite_token, token_record)
         |> assign(:client_ip, ClientIp.from_socket(socket))
         |> assign(:return_to, safe_return_to(params["return_to"]))
         |> assign_session_handoff(session)
         |> assign_form(changeset)}

      nil ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("identity", "Invalid or expired registration link."))
         |> redirect(to: PublicURLs.home_path(socket.assigns.locale))}
    end
  end

  def mount(_params, session, socket) do
    user = Accounts.new_user()
    changeset = Ecto.Changeset.cast(user, %{}, [])

    {:ok,
     socket
     |> assign(:registration_user, user)
     |> assign(:invite_token, nil)
     |> assign(:client_ip, ClientIp.from_socket(socket))
     |> assign(:return_to, nil)
     |> assign_session_handoff(session)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.check_registration_rate(socket.assigns[:client_ip] || ClientIp.missing_peer_data()) do
      :ok ->
        do_register(socket, user_params)

      {:error, :rate_limited} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           dgettext("identity", "Too many registration attempts. Please try again later.")
         )
         |> push_navigate(to: PublicURLs.home_path(socket.assigns.locale))}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = registration_changeset(socket, user_params, hash_password: false, validate_unique: false)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  # Private helpers

  defp do_register(socket, user_params) do
    case register(socket, user_params) do
      {:ok, user} ->
        {:noreply, hand_off_session(socket, user)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, :stale_invite_token} ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("identity", "Invalid or expired registration link."))
         |> push_navigate(to: PublicURLs.home_path(socket.assigns.locale))}

      {:error, reason}
      when reason in [:workspace_limit_reached, :workspace_provisioning_failed] ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("identity", "We couldn't create your workspace. Please try again.")
         )}
    end
  end

  # The account exists: the browser posts this token to UserSessionController,
  # which starts the session the same way the login form does.
  defp hand_off_session(%{assigns: %{login_handoff_nonce: nonce}} = socket, user)
       when is_binary(nonce) and nonce != "" do
    socket
    |> assign(:trigger_submit, true)
    |> assign(:login_token, UserLoginToken.sign_registration(user, nonce, socket.assigns.return_to))
  end

  defp hand_off_session(socket, _user) do
    socket
    |> put_flash(:info, dgettext("identity", "Your account was created. Log in to continue."))
    |> push_navigate(to: PublicURLs.locale_handoff_path(~p"/users/log-in", socket.assigns.locale))
  end

  defp assign_session_handoff(socket, session) do
    socket
    |> assign(:login_handoff_nonce, session["login_handoff_nonce"])
    |> assign(:trigger_submit, false)
    |> assign(:login_token, nil)
  end

  defp register(%{assigns: %{invite_token: nil}}, user_params) do
    Accounts.register_user_with_password(user_params)
  end

  defp register(%{assigns: %{registration_user: user, invite_token: token_record}}, user_params) do
    Accounts.complete_registration(user, token_record, user_params)
  end

  defp registration_changeset(%{assigns: %{invite_token: nil, registration_user: user}}, user_params, opts) do
    Accounts.change_user_registration(user, user_params, opts)
  end

  defp registration_changeset(%{assigns: %{registration_user: user}}, user_params, opts) do
    Accounts.change_user_password(user, user_params, opts)
  end

  defp safe_return_to(path) when is_binary(path) do
    uri = URI.parse(path)

    cond do
      uri.scheme || uri.host -> nil
      not String.starts_with?(path, "/") -> nil
      String.starts_with?(path, "//") -> nil
      true -> path
    end
  end

  defp safe_return_to(_path), do: nil

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
