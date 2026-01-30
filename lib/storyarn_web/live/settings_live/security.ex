defmodule StoryarnWeb.SettingsLive.Security do
  @moduledoc """
  LiveView for security settings (password management).
  """
  use StoryarnWeb, :live_view

  import StoryarnWeb.Components.SettingsLayout

  alias Storyarn.Accounts

  on_mount {StoryarnWeb.UserAuth, :require_sudo_mode}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    socket =
      socket
      |> assign(:page_title, gettext("Security Settings"))
      |> assign(:current_path, ~p"/users/settings/security")
      |> assign(:current_email, user.email)
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} workspaces={@workspaces}>
      <.settings_layout current_path={@current_path} current_scope={@current_scope}>
        <:title>{gettext("Security")}</:title>
        <:subtitle>{gettext("Manage your password and account security")}</:subtitle>

        <div class="space-y-8">
          <%!-- Password Section --%>
          <section>
            <h3 class="text-lg font-semibold mb-4">{gettext("Change Password")}</h3>
            <p class="text-sm text-base-content/70 mb-4">
              {gettext("Choose a strong password that you don't use elsewhere.")}
            </p>
            <.form
              for={@password_form}
              id="password_form"
              action={~p"/users/update-password"}
              method="post"
              phx-change="validate_password"
              phx-submit="update_password"
              phx-trigger-action={@trigger_submit}
              class="space-y-4"
            >
              <input
                name={@password_form[:email].name}
                type="hidden"
                id="hidden_user_email"
                autocomplete="username"
                value={@current_email}
              />
              <.input
                field={@password_form[:password]}
                type="password"
                label={gettext("New password")}
                autocomplete="new-password"
                required
              />
              <.input
                field={@password_form[:password_confirmation]}
                type="password"
                label={gettext("Confirm new password")}
                autocomplete="new-password"
              />
              <div class="flex justify-end">
                <.button variant="primary" phx-disable-with={gettext("Saving...")}>
                  {gettext("Update Password")}
                </.button>
              </div>
            </.form>
          </section>

          <div class="divider" />

          <%!-- Sessions Section (future) --%>
          <section>
            <h3 class="text-lg font-semibold mb-4">{gettext("Active Sessions")}</h3>
            <p class="text-sm text-base-content/70 mb-4">
              {gettext("You are currently logged in on this device.")}
            </p>
            <div class="alert alert-info">
              <.icon name="hero-information-circle" class="size-5" />
              <span>{gettext("Session management coming soon.")}</span>
            </div>
          </section>
        </div>
      </.settings_layout>
    </Layouts.app>
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
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end
end
