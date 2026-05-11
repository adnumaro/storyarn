defmodule StoryarnWeb.Components.WorkspaceLayout do
  @moduledoc """
  Workspace layout boundary.

  The HEEx component owns backend data serialization and flash rendering.
  The visual layout and workspace navigation live in the public LiveVue
  boundary `live/layouts/workspace/Layout`.
  """

  use StoryarnWeb, :html
  use Gettext, backend: Storyarn.Gettext

  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :current_workspace, :map, required: true
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

    assigns =
      assigns
      |> assign(:current_user, current_user)
      |> assign(:workspace_items, workspace_items)

    ~H"""
    <div id="layout-wrapper">
      <.vue
        v-component="live/layouts/workspace/Layout"
        v-socket={@socket}
        id="workspace-layout"
        current-user={@current_user}
        workspaces={@workspace_items}
        current-workspace-slug={@current_workspace.slug}
      />

      {render_slot(@inner_block)}

      <div id="flash-group" aria-live="polite">
        <.flash kind={:info} flash={@flash} />
        <.flash kind={:error} flash={@flash} />

        <.flash
          id="client-error"
          kind={:error}
          title={gettext("We can't find the internet")}
          phx-disconnected={
            show(".phx-client-error #client-error") |> Phoenix.LiveView.JS.remove_attribute("hidden")
          }
          phx-connected={hide("#client-error") |> Phoenix.LiveView.JS.set_attribute({"hidden", ""})}
          hidden
        >
          {gettext("Attempting to reconnect")}
          <.icon name="refresh-cw" class="ml-1 size-3 motion-safe:animate-spin" />
        </.flash>

        <.flash
          id="server-error"
          kind={:error}
          title={gettext("Something went wrong!")}
          phx-disconnected={
            show(".phx-server-error #server-error") |> Phoenix.LiveView.JS.remove_attribute("hidden")
          }
          phx-connected={hide("#server-error") |> Phoenix.LiveView.JS.set_attribute({"hidden", ""})}
          hidden
        >
          {gettext("Attempting to reconnect")}
          <.icon name="refresh-cw" class="ml-1 size-3 motion-safe:animate-spin" />
        </.flash>
      </div>
    </div>
    """
  end
end
