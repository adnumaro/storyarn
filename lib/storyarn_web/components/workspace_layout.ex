defmodule StoryarnWeb.Components.WorkspaceLayout do
  @moduledoc """
  Workspace layout boundary.

  The HEEx component owns backend data serialization and flash rendering.
  The visual layout and workspace navigation live in the public LiveVue
  boundary `live/layouts/workspace/Layout`.
  """

  use StoryarnWeb, :html

  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :current_workspace, :map, default: nil
  attr :workspaces, :list, default: []
  attr :socket, :any, required: true

  slot :inner_block, required: true

  def workspace(assigns) do
    current_user =
      case assigns.current_scope do
        %{user: user} ->
          %{
            id: user.id,
            email: user.email,
            displayName: user.display_name
          }

        _ ->
          %{id: nil, email: "", displayName: ""}
      end

    workspace_items =
      Enum.map(assigns.workspaces, fn w ->
        %{
          id: w.id,
          name: w.name,
          slug: w.slug
        }
      end)

    current_workspace_slug =
      case assigns.current_workspace do
        %{slug: slug} -> slug
        _ -> nil
      end

    assigns =
      assigns
      |> assign(:current_user, current_user)
      |> assign(:workspace_items, workspace_items)
      |> assign(:current_workspace_slug, current_workspace_slug)

    ~H"""
    <div id="layout-wrapper">
      <.vue
        v-component="live/layouts/workspace/Layout"
        v-socket={@socket}
        id="workspace-layout"
        current-user={@current_user}
        workspaces={@workspace_items}
        current-workspace-slug={@current_workspace_slug}
      />

      {render_slot(@inner_block)}

      <Layouts.flash_group flash={@flash} socket={@socket} />
    </div>
    """
  end
end
