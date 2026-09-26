defmodule StoryarnWeb.Live.Hooks.ProjectScope do
  @moduledoc """
  `on_mount` hook that loads the project context for any LiveView nested
  under a project route.

  Reads `workspace_slug` and `project_slug` from params, loads the project
  (with authorization), and assigns `:project`, `:workspace`, `:membership`,
  `:read_only`, `:can_edit` and `:can_delete` to the socket. Halts with a redirect on auth
  failure.

  While the workspace is read-only (its owner's account is over its plan's
  limits) `:can_edit` is false for everyone, so every tool renders as it does
  for a viewer. `:can_delete` stays with the role: deleting is how the owner
  gets back within the limits.

  Used by the authenticated app live_session. It is intentionally conditional:
  routes with project slugs get project context; all other authenticated routes
  pass through unchanged.
  """

  use Gettext, backend: Storyarn.Gettext
  use StoryarnWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, redirect: 2]

  alias Storyarn.Projects
  alias StoryarnWeb.Live.Shared.ProjectChromeHelpers
  alias StoryarnWeb.Live.Shared.ReadOnlyNotice

  def on_mount(:load_project, %{"workspace_slug" => ws_slug, "project_slug" => p_slug}, _session, socket) do
    case Projects.get_project_by_slugs(socket.assigns.current_scope, ws_slug, p_slug) do
      {:ok, project, membership} ->
        read_only = ReadOnlyNotice.read_only?(project.workspace_id)
        can_edit = Projects.can?(membership.role, :edit_content) and not read_only
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
          |> assign(:read_only, read_only)
          |> assign(:can_edit, can_edit)
          |> assign(:can_delete, Projects.can?(membership.role, :delete_content))
          |> assign(:current_user, current_user)
          |> assign(:urls, ProjectChromeHelpers.build_urls(project.workspace, project))

        {:cont, socket}

      {:error, _reason} ->
        socket =
          socket
          |> put_flash(:error, dgettext("projects", "You don't have access to this project."))
          |> redirect(to: ~p"/workspaces")

        {:halt, socket}
    end
  end

  # Fallback: route doesn't have project slugs. Pass through without loading.
  def on_mount(:load_project, _params, _session, socket) do
    {:cont, socket}
  end
end
