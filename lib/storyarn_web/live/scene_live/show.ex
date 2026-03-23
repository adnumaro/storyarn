defmodule StoryarnWeb.SceneLive.Show do
  @moduledoc """
  V2 Scene editor — stub for Phase 1 (routes only).
  Full implementation in Phase 2.
  """

  use StoryarnWeb, :live_view

  alias Storyarn.Projects

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.focus_v2
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      active_tool={:scenes}
      has_tree={false}
      can_edit={@can_edit}
    >
      <div class="flex items-center justify-center h-full">
        <p class="text-muted-foreground text-sm">Scene editor V2 — coming in Phase 2</p>
      </div>
    </Layouts.focus_v2>
    """
  end

  @impl true
  def mount(
        %{"workspace_slug" => workspace_slug, "project_slug" => project_slug},
        _session,
        socket
      ) do
    case Projects.get_project_by_slugs(
           socket.assigns.current_scope,
           workspace_slug,
           project_slug
         ) do
      {:ok, project, membership} ->
        can_edit = Projects.can?(membership.role, :edit_content)

        {:ok,
         socket
         |> assign(:project, project)
         |> assign(:workspace, project.workspace)
         |> assign(:can_edit, can_edit)}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("scenes", "You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}
end
