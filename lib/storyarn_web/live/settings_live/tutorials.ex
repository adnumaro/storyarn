defmodule StoryarnWeb.SettingsLive.Tutorials do
  @moduledoc """
  Account settings for restarting contextual onboarding tutorials.
  """

  use StoryarnWeb, :live_view

  alias Storyarn.Analytics
  alias Storyarn.Onboarding

  @impl true
  def mount(_params, _session, socket) do
    summary = socket.assigns.onboarding

    {:ok,
     socket
     |> assign(:page_title, dgettext("settings", "Tutorial Settings"))
     |> assign(:current_path, ~p"/users/settings/tutorials")
     |> assign(:tutorials, serialize_tutorials(summary))}
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
      onboarding={@onboarding}
    >
      <.vue
        v-component="live/account/settings/AccountSettingsTutorials"
        v-socket={@socket}
        v-inject="settings-layout"
        id="settings-tutorials-vue"
        tutorials={@tutorials}
      />
    </StoryarnWeb.Components.SettingsLayout.settings>
    """
  end

  @impl true
  def handle_event("restart_tutorial", %{"tutorial" => tutorial}, socket) do
    case Onboarding.restart_tutorial(socket.assigns.current_scope, tutorial) do
      {:ok, _progress} ->
        Analytics.track(socket.assigns.current_scope, "onboarding tutorial interacted", %{
          action: "restarted",
          guide: tutorial,
          source: "settings"
        })

        {:noreply, refresh_tutorials(socket)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  def handle_event("restart_all_tutorials", _params, socket) do
    case Onboarding.restart_all(socket.assigns.current_scope) do
      {:ok, _progress} ->
        Analytics.track(socket.assigns.current_scope, "onboarding tutorial interacted", %{
          action: "restarted",
          guide: "all",
          source: "settings"
        })

        {:noreply, refresh_tutorials(socket)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  defp refresh_tutorials(socket) do
    summary = Onboarding.summary(socket.assigns.current_scope)

    socket
    |> assign(:onboarding, summary)
    |> assign(:tutorials, serialize_tutorials(summary))
  end

  defp serialize_tutorials(summary) do
    Enum.map(Onboarding.tutorials(), fn tutorial ->
      key = Atom.to_string(tutorial)
      guide = Map.fetch!(summary.guides, key)

      %{key: key, state: Atom.to_string(guide.state)}
    end)
  end
end
