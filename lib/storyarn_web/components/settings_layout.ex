defmodule StoryarnWeb.Components.SettingsLayout do
  @moduledoc """
  LiveVue layout boundary for account, workspace, and project settings pages.

  The route LiveView owns authorization and page data. This wrapper serializes
  settings navigation context and mounts the public Vue layout boundary.
  """

  use StoryarnWeb, :html

  alias Storyarn.FeatureFlags
  alias StoryarnWeb.Live.Shared.OnboardingHelpers

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :socket, :any, required: true, doc: "the LiveView socket (needed for LiveVue)"
  attr :current_scope, :map, required: true, doc: "the current scope"
  attr :workspaces, :list, default: [], doc: "list of workspaces for settings nav data"
  attr :workspace, :map, default: nil, doc: "current workspace for project settings"
  attr :project, :map, default: nil, doc: "current project for project settings"

  attr :managed_workspace_slugs, :any,
    default: MapSet.new(),
    doc: "MapSet of workspace slugs where user has WorkspaceMembership"

  attr :current_path, :string, required: true, doc: "current settings path for nav highlighting"
  attr :sudo_grant, :string, default: nil, doc: "validated grant for sensitive settings links"
  attr :onboarding, :map, default: %{guides: %{}}
  attr :onboarding_guide, :atom, default: nil
  attr :onboarding_autostart, :boolean, default: false

  slot :title
  slot :subtitle
  slot :inner_block, required: true

  def settings(assigns) do
    # Keep serialization in the attribute expressions so HEEx can track the
    # original assign dependencies. Deriving assigns in this function body
    # marks the LiveVue boundary as changed whenever its injected page rerenders;
    # LiveVue then remounts that page and drops input focus and local form state.
    ~H"""
    <div id="settings-layout-wrapper">
      <.vue
        v-component="live/layouts/settings/Layout"
        v-socket={@socket}
        id="settings-layout"
        current-path={@current_path}
        sudo-grant={@sudo_grant}
        workspaces={settings_workspaces(@workspaces)}
        managed-workspace-slugs={settings_managed_workspace_slugs(@managed_workspace_slugs)}
        workspace={settings_workspace(@workspace)}
        project={settings_project(@project)}
        title={slot_to_text(@title)}
        subtitle={slot_to_text(@subtitle)}
        onboarding={
          OnboardingHelpers.client_config(
            @onboarding,
            @onboarding_guide,
            @onboarding_autostart
          )
        }
        feature-flags={feature_flags_for(@current_scope)}
      />

      {render_slot(@inner_block)}

      <Layouts.flash_group flash={@flash} socket={@socket} />
    </div>
    """
  end

  defp slot_to_text([]), do: nil

  defp slot_to_text(slot) do
    slot_html =
      %{}
      |> Phoenix.Component.__render_slot__(slot, nil)
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    case Floki.parse_fragment(slot_html) do
      {:ok, html_tree} -> Floki.text(html_tree)
      {:error, _reason} -> slot_html
    end
  end

  defp settings_workspaces(workspaces) do
    Enum.map(workspaces, fn workspace ->
      %{
        id: Map.get(workspace, :id),
        name: Map.get(workspace, :name),
        slug: Map.get(workspace, :slug)
      }
    end)
  end

  defp settings_managed_workspace_slugs(%MapSet{} = slugs), do: MapSet.to_list(slugs)
  defp settings_managed_workspace_slugs(slugs) when is_list(slugs), do: slugs
  defp settings_managed_workspace_slugs(_slugs), do: []

  defp settings_workspace(nil), do: nil

  defp settings_workspace(workspace) do
    %{
      id: Map.get(workspace, :id),
      name: Map.get(workspace, :name),
      slug: Map.get(workspace, :slug)
    }
  end

  defp settings_project(nil), do: nil

  defp settings_project(project) do
    %{
      id: Map.get(project, :id),
      name: Map.get(project, :name),
      slug: Map.get(project, :slug)
    }
  end

  # Serializes per-user feature flag state for the sidebar. Keys are camelCase
  # to match the Vue Layout prop convention. Extend this map as flags are added.
  defp feature_flags_for(%{user: user}) when not is_nil(user) do
    %{
      aiIntegrations: FeatureFlags.enabled?(:ai_integrations, for: user)
    }
  end

  defp feature_flags_for(_scope), do: %{aiIntegrations: false}
end
