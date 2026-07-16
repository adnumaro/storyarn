defmodule StoryarnWeb.SettingsLive.Security do
  @moduledoc """
  LiveView for security settings (password management).
  """
  use StoryarnWeb, :live_view

  alias Storyarn.Accounts
  alias StoryarnWeb.UserAuth

  on_mount {UserAuth, {:require_sudo_mode, __MODULE__}}

  @doc false
  def sudo_return_to(_params, _live_action), do: ~p"/users/settings/security"

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    socket =
      socket
      |> assign(:page_title, dgettext("settings", "Security Settings"))
      |> assign(:current_path, ~p"/users/settings/security")
      |> assign(:current_email, user.email)
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.SettingsLayout.settings
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      workspaces={@workspaces}
      managed_workspace_slugs={@managed_workspace_slugs}
      current_path={@current_path}
      sudo_grant={@sudo_grant}
    >
      <.vue
        v-component="live/account/settings/AccountSettingsSecurity"
        v-socket={@socket}
        v-inject="settings-layout"
        id="settings-security-vue"
        password-form={@password_form}
        current-email={@current_email}
        trigger-submit={@trigger_submit}
        password-action={~p"/users/update-password"}
        sudo-grant={@sudo_grant}
      />
    </StoryarnWeb.Components.SettingsLayout.settings>
    """
  end

  @impl true
  def handle_event("validate_password", %{"user" => user_params}, socket) do
    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", %{"user" => user_params}, socket) do
    user = socket.assigns.current_scope.user

    if match?(
         {:ok, _grant},
         UserAuth.authorize_sudo(
           user,
           socket.assigns.sudo_session_token,
           socket.assigns.sudo_grant
         )
       ) do
      case Accounts.change_user_password(user, user_params) do
        %{valid?: true} = changeset ->
          {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

        changeset ->
          {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
      end
    else
      {:noreply,
       push_navigate(socket,
         to: UserAuth.sudo_confirmation_path(~p"/users/settings/security"),
         replace: true
       )}
    end
  end
end
