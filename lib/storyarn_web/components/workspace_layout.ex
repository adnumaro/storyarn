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
      workspaces: ~p"/workspaces",
      logout: ~p"/users/log-out"
    }

    assigns =
      assigns
      |> assign(:current_user, current_user)
      |> assign(:formatted_workspaces, formatted_workspaces)
      |> assign(:urls, urls)

    ~H"""
    <div
      id="layout-wrapper"
      class="flex h-screen w-screen overflow-hidden"
    >
      <%!-- Hidden checkbox for mobile sidebar toggle (must be first child for peer-*) --%>
      <input id="workspace-sidebar-check" type="checkbox" class="peer hidden" />

      <%!-- Mobile overlay (closes sidebar on tap) --%>
      <label
        for="workspace-sidebar-check"
        class="fixed inset-0 bg-background/80 backdrop-blur-sm z-30 hidden peer-checked:block lg:hidden cursor-pointer"
      />
      
    <!-- Fixed Left Sidebar (Desktop) -->
      <aside class={[
        "flex-none w-[252px] surface-panel flex flex-col z-40 shrink-0 overflow-hidden rounded-lg",
        "fixed lg:relative top-3 bottom-3 left-3 lg:top-0 lg:bottom-0 lg:left-0 h-[calc(100vh-1.5rem)] lg:h-auto",
        "lg:ml-3 lg:my-3",
        "transition-transform duration-200",
        "-translate-x-[calc(100%+1rem)] peer-checked:translate-x-0 lg:translate-x-0"
      ]}>
        <.vue
          v-component="layout/WorkspaceSidebar"
          v-socket={@socket}
          id="workspace-sidebar"
          current-user={@current_user}
          urls={@urls}
          class="h-full"
          workspaces={@formatted_workspaces}
          current-workspace-slug={@current_workspace.slug}
        />
      </aside>
      
    <!-- Main fluid content -->
      <main
        id="main-content"
        class="overflow-y-auto p-4 lg:px-8 lg:py-3 min-dvh-100"
      >
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
