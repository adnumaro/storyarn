defmodule StoryarnWeb.Live.Hooks.ProjectScope do
  @moduledoc """
  `on_mount` hook that loads the project context for any LiveView nested
  under a project route.

  Reads `workspace_slug` and `project_slug` from params, loads the project
  (with authorization), and assigns `:project`, `:workspace`, `:membership`,
  and `:can_edit` to the socket. Halts with a redirect on auth failure.

  Used by `live_session :project_scope` so every page LV (SheetLive.Show,
  SheetLive.Index, future FlowLive.*, etc.) gets the project context without
  duplicating the load.
  """

  use Gettext, backend: Storyarn.Gettext
  use StoryarnWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, redirect: 2]

  alias Storyarn.Projects
  alias StoryarnWeb.Components.AppLayout

  def on_mount(
        :load_project,
        %{"workspace_slug" => ws_slug, "project_slug" => p_slug},
        _session,
        socket
      ) do
    case Projects.get_project_by_slugs(socket.assigns.current_scope, ws_slug, p_slug) do
      {:ok, project, membership} ->
        can_edit = Projects.can?(membership.role, :edit_content)
        user = socket.assigns.current_scope.user

        current_user = %{
          id: user.id,
          email: user.email,
          displayName: user.display_name,
          isSuperAdmin: user.is_super_admin
        }

        socket =
          socket
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:can_edit, can_edit)
          |> assign(:current_user, current_user)
          |> assign(:is_super_admin, user.is_super_admin)
          |> assign(:urls, AppLayout.build_urls(project.workspace, project))

        {:cont, socket}

      {:error, _reason} ->
        socket =
          socket
          |> put_flash(:error, dgettext("projects", "You don't have access to this project."))
          |> redirect(to: ~p"/workspaces")

        {:halt, socket}
    end
  end

  # Fallback: route doesn't have project slugs (shouldn't happen inside :project_scope,
  # but keep the hook safe). Just pass through without loading.
  def on_mount(:load_project, _params, _session, socket) do
    {:cont, socket}
  end
end
