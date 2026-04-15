defmodule StoryarnWeb.Components.ProjectShell do
  @moduledoc """
  Layout wrapper for all project-scoped pages (sheets, flows, scenes,
  screenplays).

  Renders the persistent chrome:
  - `ToolbarsLive` (top-left + top-right floating toolbars) as a sticky LV.
  - `SidebarLive` (project tree panel) as a sticky LV.

  Both nested LVs have stable ids keyed on project — they survive
  `live_patch`/`live_redirect` between pages in the same `live_session`.

  Usage from a page LV's render:

      <ProjectShell.project_shell
        socket={@socket}
        project={@project}
        workspace={@workspace}
        current_scope={@current_scope}
        current_user={@current_user}
        urls={@urls}
        sheet_id={@sheet_id}
        active_tool={:sheets}
        can_edit={@can_edit}
        is_super_admin={@is_super_admin}
        dashboard_url={@dashboard_url}
      >
        <!-- page-specific content -->
      </ProjectShell.project_shell>
  """

  use StoryarnWeb, :html

  attr :socket, :any, required: true
  attr :project, :map, required: true
  attr :workspace, :map, required: true
  attr :current_scope, :map, required: true
  attr :current_user, :map, required: true
  attr :urls, :map, required: true
  attr :sheet_id, :any, default: nil, doc: "passed via PubSub to sidebar; initial value only"
  attr :active_tool, :atom, default: :sheets
  attr :can_edit, :boolean, default: false
  attr :is_super_admin, :boolean, default: false
  attr :dashboard_url, :string, default: nil

  slot :inner_block, required: true

  def project_shell(assigns) do
    ~H"""
    <div class="h-screen w-screen overflow-hidden relative bg-background">
      {live_render(@socket, StoryarnWeb.ToolbarsLive,
        id: "toolbars-#{@project.id}",
        sticky: true,
        session: %{
          "project_id" => @project.id,
          "project_name" => @project.name,
          "workspace_name" => @workspace.name,
          "is_super_admin" => @is_super_admin,
          "urls" => @urls,
          "active_tool" => to_string(@active_tool),
          "current_user" => @current_user,
          "current_scope" => @current_scope
        }
      )}

      {live_render(@socket, StoryarnWeb.SidebarLive,
        id: "sidebar-#{@project.id}",
        sticky: true,
        session: %{
          "project_id" => @project.id,
          "workspace_slug" => @workspace.slug,
          "project_slug" => @project.slug,
          "sheet_id" => @sheet_id,
          "can_edit" => @can_edit,
          "active_tool" => to_string(@active_tool),
          "dashboard_url" => @dashboard_url,
          "current_scope" => @current_scope
        }
      )}

      <main
        id="main-content"
        class={[
          "h-full overflow-y-auto pt-[76px] pb-4 px-4",
          "transition-[padding-left] duration-200",
          "md:[body[data-tree-panel-open='1']_&]:pl-[320px]"
        ]}
      >
        {render_slot(@inner_block)}
      </main>
    </div>
    """
  end
end
