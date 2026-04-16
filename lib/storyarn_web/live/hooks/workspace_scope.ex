defmodule StoryarnWeb.Live.Hooks.WorkspaceScope do
  @moduledoc """
  `on_mount` hook that loads the workspace context for any LiveView nested
  under a workspace settings route.

  Reads `slug` from params, loads the workspace (with authorization), and
  assigns `:workspace` and `:membership` to the socket. Halts with a
  redirect on auth failure.

  Used by `live_session :workspace_scope` so workspace settings LVs
  (`SettingsLive.WorkspaceGeneral`, `WorkspaceMembers`,
  `WorkspaceDeletedProjects`) get the workspace context without
  duplicating the load. Each LV still owns its own permission check
  (mirrors `ProjectScope`, which only loads — never authorizes).
  """

  use Gettext, backend: Storyarn.Gettext
  use StoryarnWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, redirect: 2]

  alias Storyarn.Workspaces

  def on_mount(:load_workspace, %{"slug" => slug}, _session, socket) do
    case Workspaces.get_workspace_by_slug(socket.assigns.current_scope, slug) do
      {:ok, workspace, membership} ->
        socket =
          socket
          |> assign(:workspace, workspace)
          |> assign(:membership, membership)

        {:cont, socket}

      {:error, _reason} ->
        socket =
          socket
          |> put_flash(:error, dgettext("workspaces", "Workspace not found."))
          |> redirect(to: ~p"/users/settings")

        {:halt, socket}
    end
  end

  # Fallback: route doesn't have a workspace slug. Pass through.
  def on_mount(:load_workspace, _params, _session, socket) do
    {:cont, socket}
  end
end
