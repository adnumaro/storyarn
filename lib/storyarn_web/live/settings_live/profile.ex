defmodule StoryarnWeb.SettingsLive.Profile do
  @moduledoc """
  LiveView for user profile settings.
  """
  use StoryarnWeb, :live_view

  alias Storyarn.Accounts
  alias Storyarn.Accounts.Scope

  on_mount {StoryarnWeb.UserAuth, :require_sudo_mode}

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, dgettext("settings", "Email changed successfully."))

        {:error, :transaction_aborted} ->
          put_flash(
            socket,
            :error,
            dgettext("settings", "Email change link is invalid or it has expired.")
          )
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    profile_changeset = Accounts.change_user_profile(user, %{})

    socket =
      socket
      |> assign(:page_title, dgettext("settings", "Profile Settings"))
      |> assign(:current_path, ~p"/users/settings")
      |> assign(:profile_form, to_form(profile_changeset))

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
    >
      <.vue
        v-component="live/account/settings/AccountSettingsProfile"
        v-socket={@socket}
        v-inject="settings-layout"
        id="settings-profile-vue"
        profile-form={@profile_form}
      />
    </StoryarnWeb.Components.SettingsLayout.settings>
    """
  end

  @impl true
  def handle_event("validate_profile", %{"user" => user_params}, socket) do
    profile_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_profile(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, profile_form: profile_form)}
  end

  def handle_event("update_profile", %{"user" => user_params}, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.update_user_profile(user, user_params) do
      {:ok, updated_user} ->
        profile_form =
          updated_user
          |> Accounts.change_user_profile(%{})
          |> to_form()

        socket =
          socket
          |> assign(:current_scope, Scope.for_user(updated_user))
          |> assign(:profile_form, profile_form)
          |> maybe_apply_locale(updated_user.locale)

        {:noreply, put_flash(socket, :info, dgettext("settings", "Profile updated successfully."))}

      {:error, changeset} ->
        {:noreply, assign(socket, profile_form: to_form(changeset, action: :insert))}
    end
  end

  defp maybe_apply_locale(socket, nil), do: socket

  defp maybe_apply_locale(socket, locale) do
    Gettext.put_locale(Storyarn.Gettext, locale)

    socket
    |> assign(:locale, locale)
    |> push_event("set-locale", %{locale: locale})
  end
end
