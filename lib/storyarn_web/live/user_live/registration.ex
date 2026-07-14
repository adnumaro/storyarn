defmodule StoryarnWeb.UserLive.Registration do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias Storyarn.Accounts
  alias Storyarn.RateLimiter
  alias StoryarnWeb.ClientIp

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
        login-url={~p"/users/log-in"}
      />
    </StoryarnWeb.Components.AuthLayout.auth>
    """
  end

  @impl true
  def mount(%{"token" => token} = params, _session, socket) do
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
         |> assign_form(changeset)}

      nil ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("identity", "Invalid or expired registration link."))
         |> redirect(to: ~p"/")}
    end
  end

  def mount(_params, _session, socket) do
    user = %Accounts.User{}
    changeset = Ecto.Changeset.cast(user, %{}, [])

    {:ok,
     socket
     |> assign(:registration_user, user)
     |> assign(:invite_token, nil)
     |> assign(:client_ip, ClientIp.from_socket(socket))
     |> assign(:return_to, nil)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case RateLimiter.check_registration(socket.assigns[:client_ip] || ClientIp.missing_peer_data()) do
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
    changeset = registration_changeset(socket, user_params, hash_password: false, validate_unique: false)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  # Private helpers

  defp do_register(socket, user_params) do
    case register(socket, user_params) do
      {:ok, _updated_user} ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("identity", "Account created successfully! Welcome."))
         |> push_navigate(to: socket.assigns.return_to || ~p"/users/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, :stale_invite_token} ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("identity", "Invalid or expired registration link."))
         |> push_navigate(to: ~p"/")}

      {:error, :workspace_limit_reached} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("identity", "We couldn't create your workspace. Please try again.")
         )}
    end
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
