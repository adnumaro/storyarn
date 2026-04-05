defmodule StoryarnWeb.Components.WorkspaceLayout do
  @moduledoc """
  Workspace layout — Used exclusively for the workspace dashboard page.
  Provides a clean, static left sidebar and main fluid content area.
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

    formatted_workspaces =
      Enum.map(assigns.workspaces, fn w ->
        %{
          id: w.id,
          name: w.name,
          slug: w.slug,
          href: ~p"/workspaces/#{w.slug}"
        }
      end)

    urls = %{
      accountSettings: ~p"/users/settings",
      workspaces: ~p"/workspaces"
    }

    assigns =
      assigns
      |> assign(:current_user, current_user)
      |> assign(:formatted_workspaces, formatted_workspaces)
      |> assign(:urls, urls)

    ~H"""
    <div id="layout-wrapper" class="flex h-screen w-screen overflow-hidden bg-background">
      <!-- Fixed Left Sidebar (Desktop) -->
      <aside class="flex-none w-[252px] ml-3 my-3 v2-surface-panel hidden md:flex flex-col z-10 rounded-lg overflow-hidden shrink-0">
        <.vue
          v-component="layout/WorkspaceSidebar"
          v-socket={@socket}
          id="workspace-sidebar"
          current-user={@current_user}
          urls={@urls}
          workspaces={@formatted_workspaces}
          current-workspace-slug={@current_workspace.slug}
        />
      </aside>

      <!-- Main fluid content -->
      <main id="main-content" class="flex-1 min-w-0 overflow-y-auto bg-background p-4 md:px-8 md:py-3 min-vh-100">
        {render_slot(@inner_block)}
      </main>

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
