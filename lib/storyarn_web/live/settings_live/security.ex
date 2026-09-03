defmodule StoryarnWeb.SettingsLive.Security do
  @moduledoc """
  Personal › Security: password management.

  The password section locks in place when the sudo window has lapsed; the
  page re-authenticates through `StoryarnWeb.Live.Shared.SudoReauth`. The
  password change itself is a native POST so the session cookie rotates.
  """
  use StoryarnWeb, :live_view

  alias Storyarn.Accounts
  alias StoryarnWeb.Live.Shared.SudoReauth
  alias StoryarnWeb.UserAuth

  on_mount {UserAuth, :load_sudo_state}

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
      |> SudoReauth.assign_reauth(~p"/users/settings/security")

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.SettingsLayout.settings
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      current_path={@current_path}
      settings_nav={@settings_nav}
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
        sudo-active={@sudo_active}
        reauth={SudoReauth.reauth_props(@sudo_return_to, @sudo_handoff, @trigger_sudo_submit)}
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
    SudoReauth.with_sudo(socket, fn socket ->
      case Accounts.change_user_password(socket.assigns.current_scope.user, user_params) do
        %{valid?: true} = changeset ->
          {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

        changeset ->
          {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
      end
    end)
  end

  def handle_event("confirm_access", params, socket) do
    SudoReauth.confirm(socket, params)
  end
end
