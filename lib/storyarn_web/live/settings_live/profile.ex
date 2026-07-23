defmodule StoryarnWeb.SettingsLive.Profile do
  @moduledoc """
  LiveView for user profile settings.
  """
  use StoryarnWeb, :live_view

  alias Storyarn.Accounts
  alias Storyarn.Accounts.Scope
  alias Storyarn.Localization.Languages
  alias StoryarnWeb.LanguagePickerOption
  alias StoryarnWeb.UserAuth

  on_mount {UserAuth, {:require_sudo_mode, __MODULE__}}

  @doc false
  def sudo_return_to(%{"token" => token}, :confirm_email) do
    ~p"/users/settings/confirm-email/#{token}"
  end

  def sudo_return_to(_params, _live_action), do: ~p"/users/settings"

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

    return_to = UserAuth.with_sudo_grant(~p"/users/settings", socket.assigns.sudo_grant)
    {:ok, push_navigate(socket, to: return_to)}
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
      general_workspace_slugs={@general_workspace_slugs}
      current_path={@current_path}
      sudo_grant={@sudo_grant}
    >
      <.vue
        v-component="live/account/settings/AccountSettingsProfile"
        v-socket={@socket}
        v-inject="settings-layout"
        id="settings-profile-vue"
        profile-form={@profile_form}
        locale-options={locale_options()}
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

    case UserAuth.authorize_sudo(
           user,
           socket.assigns.sudo_session_token,
           socket.assigns.sudo_grant
         ) do
      {:ok, _grant} -> update_profile(socket, user, user_params)
      :error -> require_sudo(socket)
    end
  end

  defp update_profile(socket, user, user_params) do
    case Accounts.update_user_profile(user, user_params) do
      {:ok, updated_user} ->
        # `authenticated_at` is virtual and is therefore lost when Ecto returns
        # the updated row. Preserve the current session's sudo timestamp so a
        # second save in the same LiveView does not spuriously require another
        # password confirmation.
        updated_user = %{updated_user | authenticated_at: user.authenticated_at}

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

  defp require_sudo(socket) do
    {:noreply,
     push_navigate(socket,
       to: UserAuth.sudo_confirmation_path(~p"/users/settings"),
       replace: true
     )}
  end

  defp maybe_apply_locale(socket, nil), do: socket

  defp maybe_apply_locale(socket, locale) do
    Gettext.put_locale(Storyarn.Gettext, locale)

    socket
    |> assign(:locale, locale)
    |> push_event("set-locale", %{locale: locale})
  end

  defp locale_options do
    Enum.map(Gettext.known_locales(Storyarn.Gettext), fn locale ->
      label =
        case Languages.get(locale) do
          %{native: native} -> native
          nil -> String.upcase(locale)
        end

      LanguagePickerOption.from_code(locale, label: label)
    end)
  end
end
