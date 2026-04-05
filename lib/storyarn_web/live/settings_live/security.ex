defmodule StoryarnWeb.SettingsLive.Security do
  @moduledoc """
  LiveView for security settings (password management).
  """
  use StoryarnWeb, :live_view

  alias Storyarn.Accounts

  on_mount {StoryarnWeb.UserAuth, :require_sudo_mode}

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
    <Layouts.settings
      flash={@flash}
      current_scope={@current_scope}
      workspaces={@workspaces}
      managed_workspace_slugs={@managed_workspace_slugs}
      current_path={@current_path}
    >
      <:title>{dgettext("settings", "Security")}</:title>
      <:subtitle>{dgettext("settings", "Manage your password and account security")}</:subtitle>

      <.vue
        v-component="pages/settings/Security"
        v-socket={@socket}
        id="settings-security-vue"
        password-form={@password_form}
        current-email={@current_email}
        trigger-submit={@trigger_submit}
        password-action={~p"/users/update-password"}
        translations={security_translations()}
      />
    </Layouts.settings>
    """
  end

  defp security_translations do
    %{
      changePassword: dgettext("settings", "Change Password"),
      passwordDescription:
        dgettext("settings", "Choose a strong password that you don't use elsewhere."),
      newPassword: dgettext("settings", "New password"),
      confirmPassword: dgettext("settings", "Confirm new password"),
      updatePassword: dgettext("settings", "Update Password"),
      activeSessions: dgettext("settings", "Active Sessions"),
      sessionsDescription: dgettext("settings", "You are currently logged in on this device."),
      sessionsComingSoon: dgettext("settings", "Session management coming soon.")
    }
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
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end
end
