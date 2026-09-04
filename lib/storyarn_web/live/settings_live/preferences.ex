defmodule StoryarnWeb.SettingsLive.Preferences do
  @moduledoc """
  Personal › Preferences: interface language and appearance.

  The language is stored on the user; the theme is a per-browser preference
  the page component keeps in local storage.
  """
  use StoryarnWeb, :live_view

  alias Storyarn.Accounts
  alias StoryarnWeb.Helpers.SaveStatusTimer
  alias StoryarnWeb.LanguagePickerOption
  alias StoryarnWeb.PublicLanguageMetadata

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    socket =
      socket
      |> assign(:page_title, dgettext("settings", "Preferences"))
      |> assign(:current_path, ~p"/users/settings/preferences")
      |> assign(:locale, user.locale || Gettext.get_locale(Storyarn.Gettext))
      |> assign(:locale_options, locale_options())
      |> assign(:save_status, :idle)

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
    >
      <.vue
        v-component="live/account/settings/AccountSettingsPreferences"
        v-socket={@socket}
        v-inject="settings-layout"
        id="settings-preferences-vue"
        locale={@locale}
        locale-options={@locale_options}
        save-status={Atom.to_string(@save_status)}
      />
    </StoryarnWeb.Components.SettingsLayout.settings>
    """
  end

  @impl true
  def handle_event("update_locale", %{"locale" => locale}, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.update_user_profile(user, %{"locale" => locale}) do
      {:ok, updated_user} ->
        # `authenticated_at` is virtual; keep the session's value so other
        # settings pages do not spuriously ask for the password again.
        updated_user = %{updated_user | authenticated_at: user.authenticated_at}
        Gettext.put_locale(Storyarn.Gettext, updated_user.locale)

        socket =
          socket
          |> assign(:current_scope, Accounts.scope_for_user(updated_user))
          |> assign(:locale, updated_user.locale)
          |> push_event("set-locale", %{locale: updated_user.locale})
          |> SaveStatusTimer.mark_saved()

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, dgettext("settings", "Could not update the language."))}
    end
  end

  @impl true
  def handle_info({:reset_save_status, token}, socket) do
    if socket.assigns[:save_status_reset_token] == token do
      {:noreply, assign(socket, :save_status, :idle)}
    else
      {:noreply, socket}
    end
  end

  defp locale_options do
    Enum.map(Gettext.known_locales(Storyarn.Gettext), fn locale ->
      label = PublicLanguageMetadata.native_name(locale)

      LanguagePickerOption.from_code(locale, label: label)
    end)
  end
end
