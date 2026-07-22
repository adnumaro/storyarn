defmodule StoryarnWeb.Components.ProjectLayout do
  @moduledoc """
  LiveVue layout boundary for project-scoped tools.

  The route LiveView owns server-backed persistent children such as presence and
  the active tool sidebar. The visual layout is a public Vue boundary that
  receives route-specific public children through LiveVue injection slots.
  """

  use StoryarnWeb, :html

  alias StoryarnWeb.Live.Shared.OnboardingHelpers

  attr :id, :string, default: "project-layout"
  attr :flash, :map, default: %{}
  attr :socket, :any, required: true
  attr :project, :map, required: true
  attr :workspace, :map, required: true
  attr :current_scope, :map, required: true
  attr :current_user, :map, required: true
  attr :membership, :map, required: true
  attr :urls, :map, required: true
  attr :active_tool, :atom, default: :sheets
  attr :is_super_admin, :boolean, default: false
  attr :online_users, :list, default: []
  attr :sidebar_module, :atom, default: nil
  attr :sidebar_session, :map, default: %{}
  attr :restoration_banner, :map, default: nil
  attr :canvas_mode, :boolean, default: false
  attr :onboarding, :map, default: %{guides: %{}}
  attr :onboarding_autostart, :boolean, default: false

  slot :inner_block, required: true

  def project(assigns) do
    ~H"""
    <div class="project-layout-frame relative h-screen w-screen overflow-hidden bg-surface">
      {live_render(@socket, StoryarnWeb.PresenceLive,
        id: "presence-#{@project.id}",
        sticky: true,
        session: %{
          "project_id" => @project.id,
          "current_scope" => @current_scope
        }
      )}

      <%= if @sidebar_module do %>
        <aside class="absolute inset-y-0 left-0 z-0 w-[calc(100vw-4rem)] overflow-hidden sm:w-63">
          {live_render(@socket, @sidebar_module,
            id: "sidebar-#{@active_tool}-#{@project.id}",
            sticky: true,
            session: @sidebar_session
          )}
        </aside>
      <% end %>

      <.vue
        v-component="live/layouts/project/Layout"
        v-socket={@socket}
        id={@id}
        class="h-full w-full overflow-hidden pointer-events-none"
        chrome={
          %{
            activeTool: to_string(@active_tool),
            hasTree: @sidebar_module != nil,
            mainSidebarOpen: true,
            projectName: @project.name,
            workspaceName: @workspace.name,
            showToolSwitcher: true,
            isSuperAdmin: @is_super_admin,
            canManageProject: Storyarn.Projects.can?(@membership.role, :manage_project)
          }
        }
        current-user={@current_user}
        online-users={@online_users}
        urls={@urls}
        restoration-banner={@restoration_banner}
        canvas-mode={@canvas_mode}
        onboarding={OnboardingHelpers.client_config(@onboarding, @active_tool, @onboarding_autostart)}
      />

      {render_slot(@inner_block)}

      <Layouts.command_palette socket={@socket} current_scope={@current_scope} />
      <Layouts.flash_group flash={@flash} socket={@socket} />
    </div>
    """
  end
end
