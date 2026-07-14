defmodule StoryarnWeb.UserLive.ResetPassword do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias Storyarn.Accounts
  alias Storyarn.Accounts.User
  alias StoryarnWeb.UserAuth

  on_mount {UserAuth, :redirect_if_user_is_authenticated}

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
        v-component="live/auth/reset-password/AuthResetPasswordForm"
        v-socket={@socket}
        v-inject="auth-layout"
        id="reset-password-vue"
        form={@form}
        login-url={~p"/users/log-in"}
        reset-complete={@reset_complete}
      />
    </StoryarnWeb.Components.AuthLayout.auth>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case Accounts.get_user_by_reset_password_token(token) do
      %User{} = user ->
        {:ok,
         socket
         |> assign(:token, token)
         |> assign(:user, user)
         |> assign(:reset_complete, false)
         |> assign_form(Accounts.change_user_password(user, %{}, hash_password: false))}

      nil ->
        {:ok, invalid_token_redirect(socket)}
    end
  end

  @impl true
  def handle_event("validate", _params, %{assigns: %{reset_complete: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset =
      socket.assigns.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("reset_password", _params, %{assigns: %{reset_complete: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("reset_password", %{"user" => user_params}, socket) do
    case Accounts.get_user_by_reset_password_token(socket.assigns.token) do
      %User{} = user ->
        reset_password(socket, user, user_params)

      nil ->
        {:noreply, invalid_token_redirect(socket)}
    end
  end

  defp reset_password(socket, user, user_params) do
    case Accounts.reset_user_password(user, user_params) do
      {:ok, {_user, expired_tokens}} ->
        UserAuth.disconnect_sessions(expired_tokens)

        {:noreply,
         socket
         |> assign(:reset_complete, true)
         |> assign(:token, nil)
         |> assign(:user, nil)}

      {:error, changeset} ->
        {:noreply, assign_form(socket, Map.put(changeset, :action, :insert))}
    end
  end

  defp invalid_token_redirect(socket) do
    socket
    |> put_flash(:error, dgettext("identity", "Invalid or expired password reset link."))
    |> redirect(to: ~p"/users/reset-password")
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "user"))
  end
end
