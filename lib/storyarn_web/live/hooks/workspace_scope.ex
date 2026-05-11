defmodule StoryarnWeb.Live.Hooks.WorkspaceScope do
  @moduledoc """
  `on_mount` hook that loads the workspace context for authenticated workspace
  routes.

  Reads either `slug` (workspace settings) or `workspace_slug` (workspace
  dashboard), loads the workspace with authorization, and assigns `:workspace`,
  `:current_workspace`, and `:membership` to the socket. Halts with a redirect
  on auth failure.

  Used by the authenticated app live_session. It is intentionally conditional:
  project routes pass through because `ProjectScope` already assigns their
  workspace; workspace-scoped routes get workspace context; all other
  authenticated routes pass through unchanged. Each LV still owns its own
  permission check (mirrors `ProjectScope`, which only loads — never
  authorizes).
  """

  use Gettext, backend: Storyarn.Gettext
  use StoryarnWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, redirect: 2]

  alias Storyarn.Workspaces

  def on_mount(:load_workspace, %{"slug" => slug}, _session, socket) do
    load_workspace(socket, slug, ~p"/users/settings")
  end

  def on_mount(:load_workspace, %{"workspace_slug" => _workspace_slug, "project_slug" => _project_slug}, _session, socket) do
    {:cont, socket}
  end

  def on_mount(:load_workspace, %{"workspace_slug" => slug}, _session, socket) do
    load_workspace(socket, slug, ~p"/workspaces")
  end

  # Fallback: route doesn't have a workspace slug. Pass through.
  def on_mount(:load_workspace, _params, _session, socket) do
    {:cont, socket}
  end

  defp load_workspace(socket, slug, redirect_to) do
    case Workspaces.get_workspace_by_slug(socket.assigns.current_scope, slug) do
      {:ok, workspace, membership} ->
        socket =
          socket
          |> assign(:workspace, workspace)
          |> assign(:current_workspace, workspace)
          |> assign(:membership, membership)

        {:cont, socket}

      {:error, _reason} ->
        socket =
          socket
          |> put_flash(:error, dgettext("workspaces", "Workspace not found."))
          |> redirect(to: redirect_to)

        {:halt, socket}
    end
  end
end
