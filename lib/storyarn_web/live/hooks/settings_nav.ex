defmodule StoryarnWeb.Live.Hooks.SettingsNav do
  @moduledoc """
  Builds the navigation context of the settings shell for every settings
  LiveView, so the rail can list the personal, workspace and project settings
  the user can reach without each page assembling that data itself.

  The hook is registered on the authenticated live session and only does work
  for settings views. It attaches a `handle_params` hook because workspace
  settings pages load their workspace inside `mount/3`, after session hooks
  have run; by `handle_params` every scope assign the rail needs is in place.
  """

  import Phoenix.Component, only: [assign: 3, assign_new: 3]

  alias Storyarn.Projects

  @settings_prefixes ["StoryarnWeb.SettingsLive.", "StoryarnWeb.ProjectSettingsLive."]
  @settings_views [StoryarnWeb.ExportImportLive.Index]

  def on_mount(:load_settings_nav, _params, _session, socket) do
    if settings_view?(socket.view) do
      socket =
        socket
        |> assign_new(:settings_nav, fn -> nil end)
        |> Phoenix.LiveView.attach_hook(:settings_nav, :handle_params, &assign_settings_nav/3)

      {:cont, socket}
    else
      {:cont, socket}
    end
  end

  defp settings_view?(view) when is_atom(view) and not is_nil(view) do
    # `inspect/1` drops the `Elixir.` prefix that `Atom.to_string/1` keeps.
    name = inspect(view)
    view in @settings_views or Enum.any?(@settings_prefixes, &String.starts_with?(name, &1))
  end

  defp settings_view?(_view), do: false

  defp assign_settings_nav(_params, _uri, socket) do
    {:cont, assign(socket, :settings_nav, build_nav(socket.assigns))}
  end

  @doc false
  def build_nav(assigns) do
    user = assigns.current_scope.user
    workspaces = workspace_entries(assigns, user)
    workspace = current_workspace(assigns, workspaces)
    project = project_entry(assigns, user)

    %{
      workspace: workspace,
      workspaces: workspaces,
      project: project,
      projects: project_options(assigns, project)
    }
  end

  defp workspace_entries(assigns, user) do
    managed = slug_set(Map.get(assigns, :managed_workspace_slugs))
    general = slug_set(Map.get(assigns, :general_workspace_slugs))

    assigns
    |> Map.get(:workspaces, [])
    |> Enum.map(fn workspace ->
      access =
        cond do
          MapSet.member?(managed, workspace.slug) -> "manage"
          MapSet.member?(general, workspace.slug) -> "general"
          true -> nil
        end

      %{
        id: workspace.id,
        slug: workspace.slug,
        name: workspace.name,
        access: access,
        owner: Map.get(workspace, :owner_id) == user.id
      }
    end)
    |> Enum.reject(&is_nil(&1.access))
  end

  defp slug_set(%MapSet{} = slugs), do: slugs
  defp slug_set(slugs) when is_list(slugs), do: MapSet.new(slugs)
  defp slug_set(_slugs), do: MapSet.new()

  defp current_workspace(assigns, workspaces) do
    scoped = Map.get(assigns, :workspace) || Map.get(assigns, :current_workspace)

    case scoped do
      %{slug: slug} ->
        # A workspace the user only views is not listed: viewers have no
        # workspace settings, so the rail hides the group entirely.
        Enum.find(workspaces, &(&1.slug == slug))

      _ ->
        List.first(workspaces)
    end
  end

  # The project entry does not depend on the workspace being listed: a viewer
  # still gets `access: "viewer"`, which the rail uses to hide the group while
  # "Back to app" keeps pointing at the project.
  defp project_entry(assigns, user) do
    with %{id: _} = project <- Map.get(assigns, :project),
         %{id: workspace_id, slug: workspace_slug} <- Map.get(assigns, :workspace),
         true <- project.workspace_id == workspace_id do
      %{
        id: project.id,
        slug: project.slug,
        name: project.name,
        workspaceSlug: workspace_slug,
        access: project_access(project, Map.get(assigns, :membership), user)
      }
    else
      _ -> nil
    end
  end

  defp project_access(project, membership, user) do
    cond do
      project.owner_id == user.id -> "owner"
      match?(%{role: _}, membership) and Projects.can?(membership.role, :edit_content) -> "editor"
      true -> "viewer"
    end
  end

  # Viewers have no project settings, so the switcher has nothing to offer them.
  defp project_options(_assigns, nil), do: []
  defp project_options(_assigns, %{access: "viewer"}), do: []

  defp project_options(assigns, _project) do
    user = assigns.current_scope.user

    case Map.get(assigns, :project) do
      %{workspace_id: workspace_id} ->
        workspace_id
        |> Projects.list_projects_for_workspace(assigns.current_scope)
        |> Enum.reject(&project_viewer?(&1, user))
        |> Enum.map(fn %{project: project} ->
          %{id: project.id, slug: project.slug, name: project.name}
        end)

      _ ->
        []
    end
  end

  # `list_projects_for_workspace/2` returns the project with the roles that
  # grant access to it; only projects the user can act on belong in the switcher.
  defp project_viewer?(%{project: project, project_role: project_role, workspace_role: workspace_role}, user) do
    role = Projects.effective_role(project_role, workspace_role)
    project.owner_id != user.id and not Projects.can?(role, :edit_content)
  end
end
