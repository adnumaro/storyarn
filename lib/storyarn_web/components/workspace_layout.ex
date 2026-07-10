defmodule StoryarnWeb.Components.WorkspaceLayout do
  @moduledoc """
  Workspace layout boundary.

  The HEEx component owns backend data serialization and flash rendering.
  The visual layout and workspace navigation live in the public LiveVue
  boundary `live/layouts/workspace/Layout`.
  """

  use StoryarnWeb, :html

  alias StoryarnWeb.Live.Shared.OnboardingHelpers

  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :current_workspace, :map, default: nil
  attr :workspaces, :list, default: []
  attr :socket, :any, required: true
  attr :onboarding, :map, default: %{eligible: false, guides: %{}}
  attr :onboarding_guide, :atom, default: nil
  attr :onboarding_autostart, :boolean, default: false

  slot :inner_block, required: true

  def workspace(assigns) do
    # Serialization happens inline in the attr expressions (like ProjectLayout)
    # so LiveView change tracking works: computing these via assign/3 in the
    # function body marks them changed on EVERY render, which re-patches the
    # layout <.vue> element whenever the slot re-renders. LiveVue then re-syncs
    # its injection slots and REMOUNTS every v-inject'ed child (dashboard state,
    # open modals, and in-progress typing are lost).
    ~H"""
    <div id="layout-wrapper">
      <.vue
        v-component="live/layouts/workspace/Layout"
        v-socket={@socket}
        id="workspace-layout"
        current-user={serialize_current_user(@current_scope)}
        workspaces={serialize_workspaces(@workspaces)}
        current-workspace-slug={workspace_slug(@current_workspace)}
        onboarding={
          OnboardingHelpers.client_config(
            @onboarding,
            @onboarding_guide,
            @onboarding_autostart
          )
        }
      />

      {render_slot(@inner_block)}

      <Layouts.flash_group flash={@flash} socket={@socket} />
    </div>
    """
  end

  defp serialize_current_user(%{user: user}) do
    %{id: user.id, email: user.email, displayName: user.display_name}
  end

  defp serialize_current_user(_current_scope), do: %{id: nil, email: "", displayName: ""}

  defp serialize_workspaces(workspaces) do
    Enum.map(workspaces, &%{id: &1.id, name: &1.name, slug: &1.slug})
  end

  defp workspace_slug(%{slug: slug}), do: slug
  defp workspace_slug(_current_workspace), do: nil
end
