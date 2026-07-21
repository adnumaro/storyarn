defmodule Storyarn.GlobalSearch.Destinations do
  @moduledoc """
  Builds the authorized destination set for a scope.

  Authorization is COMPOSED from the existing membership-scoped queries —
  `Workspaces.list_workspaces/1` (includes project-membership-only
  visibility) and `Projects.list_projects_for_workspace/2` — never
  re-derived here. Entity searches receive project ids exclusively from
  that pre-authorized set.
  """

  alias Storyarn.Accounts.Scope
  alias Storyarn.Flows
  alias Storyarn.Projects
  alias Storyarn.Scenes
  alias Storyarn.Sheets
  alias Storyarn.Workspaces

  @max_query_length 100
  @min_entity_query_length 2
  @default_limit_per_type 8

  @type destination :: %{
          required(:type) => :workspace | :project | :sheet | :flow | :scene,
          required(:id) => integer(),
          required(:name) => String.t(),
          required(:workspace_slug) => String.t(),
          optional(:role) => String.t() | nil,
          optional(:project_id) => integer(),
          optional(:project_slug) => String.t(),
          optional(:project_name) => String.t(),
          optional(:shortcut) => String.t() | nil
        }

  @spec destinations(Scope.t(), String.t(), keyword()) :: %{
          workspaces: [destination()],
          projects: [destination()],
          entities: [destination()]
        }
  def destinations(%Scope{} = scope, query, opts \\ []) do
    limit = Keyword.get(opts, :limit_per_type, @default_limit_per_type)
    query = normalize_query(query)

    %{workspace_entries: workspace_entries, workspace_by_id: workspace_by_id, project_entries: project_entries} =
      authorized_entries(scope)

    projects_by_id = Map.new(project_entries, fn %{project: p} -> {p.id, p} end)

    %{
      workspaces:
        workspace_entries
        |> Enum.filter(&String.contains?(String.downcase(&1.workspace.name), String.downcase(query)))
        |> Enum.take(limit)
        |> Enum.map(&workspace_destination/1),
      projects:
        project_entries
        |> Enum.map(& &1.project)
        |> filter_by_name(query)
        |> Enum.take(limit)
        |> Enum.map(&project_destination(&1, workspace_by_id)),
      entities: entity_destinations(projects_by_id, workspace_by_id, query, limit)
    }
  end

  @doc """
  Projects where the scope's user can create content (effective role allows
  `:edit_content`), for the palette's create picker. Unbounded on purpose:
  the picker filters client-side over the full authorized set.
  """
  @spec create_targets(Scope.t()) :: [
          %{id: integer(), name: String.t(), workspace_name: String.t()}
        ]
  def create_targets(%Scope{} = scope) do
    scope
    |> editable_project_entries()
    |> Enum.map(fn %{project: project, workspace: workspace} ->
      %{id: project.id, name: project.name, workspace_name: workspace.name}
    end)
  end

  @doc """
  Authorizes `project_id` for content mutations. The id is validated against
  the composed editable set — never trusted from the caller.
  """
  @spec editable_project(Scope.t(), integer()) ::
          {:ok, %{project: struct(), workspace: struct()}} | {:error, :unauthorized}
  def editable_project(%Scope{} = scope, project_id) do
    case Enum.find(editable_project_entries(scope), &(&1.project.id == project_id)) do
      nil -> {:error, :unauthorized}
      entry -> {:ok, entry}
    end
  end

  @doc """
  Entity search restricted to projects the user can edit — the candidate set
  for destructive palette actions. Unlike `destinations/3`, an empty query
  lists the most recently updated entities: a destructive picker must let
  the user browse before typing.
  """
  @spec deletable_entities(Scope.t(), String.t(), keyword()) :: [destination()]
  def deletable_entities(%Scope{} = scope, query, opts \\ []) do
    limit = Keyword.get(opts, :limit_per_type, @default_limit_per_type)
    query = normalize_query(query)

    entries = editable_project_entries(scope)
    projects_by_id = Map.new(entries, fn %{project: p} -> {p.id, p} end)
    workspace_by_id = Map.new(entries, fn %{project: p, workspace: w} -> {p.workspace_id, w} end)

    if map_size(projects_by_id) == 0 do
      []
    else
      run_entity_searches(projects_by_id, workspace_by_id, query, limit)
    end
  end

  @doc """
  Authorizes and loads one entity for deletion: the project must be editable
  for the scope AND the entity must live in that project (scoped, soft-delete
  filtered load). Both ids come from the client and are re-validated here.
  """
  @spec deletable_entity(Scope.t(), :sheet | :flow | :scene, integer(), integer()) ::
          {:ok, %{entity: struct(), project: struct(), workspace: struct()}}
          | {:error, :unauthorized | :not_found}
  def deletable_entity(%Scope{} = scope, type, project_id, id) when type in [:sheet, :flow, :scene] do
    with {:ok, %{project: project, workspace: workspace}} <- editable_project(scope, project_id),
         %{} = entity <- get_entity(type, project.id, id) do
      {:ok, %{entity: entity, project: project, workspace: workspace}}
    else
      {:error, :unauthorized} -> {:error, :unauthorized}
      nil -> {:error, :not_found}
    end
  end

  defp get_entity(:sheet, project_id, id), do: Sheets.get_sheet(project_id, id)
  defp get_entity(:flow, project_id, id), do: Flows.get_flow(project_id, id)
  defp get_entity(:scene, project_id, id), do: Scenes.get_scene(project_id, id)

  defp authorized_entries(%Scope{} = scope) do
    workspace_entries = Workspaces.list_workspaces(scope)
    workspace_by_id = Map.new(workspace_entries, fn %{workspace: w} -> {w.id, w} end)

    project_entries =
      workspace_entries
      |> Enum.flat_map(fn %{workspace: workspace} ->
        Projects.list_projects_for_workspace(workspace.id, scope)
      end)
      |> Enum.uniq_by(& &1.project.id)

    %{workspace_entries: workspace_entries, workspace_by_id: workspace_by_id, project_entries: project_entries}
  end

  defp editable_project_entries(%Scope{} = scope) do
    %{workspace_by_id: workspace_by_id, project_entries: project_entries} = authorized_entries(scope)

    project_entries
    |> Enum.filter(fn entry ->
      entry.project_role
      |> Projects.effective_role(entry.workspace_role)
      |> Projects.can?(:edit_content)
    end)
    |> Enum.map(fn %{project: project} ->
      %{project: project, workspace: workspace_by_id[project.workspace_id]}
    end)
  end

  defp normalize_query(query) do
    query |> to_string() |> String.slice(0, @max_query_length) |> String.trim()
  end

  defp filter_by_name(items, ""), do: items

  defp filter_by_name(items, query) do
    downcased = String.downcase(query)
    Enum.filter(items, &String.contains?(String.downcase(&1.name), downcased))
  end

  defp workspace_destination(%{workspace: workspace, role: role}) do
    %{
      type: :workspace,
      id: workspace.id,
      name: workspace.name,
      workspace_slug: workspace.slug,
      role: role
    }
  end

  defp project_destination(project, workspace_by_id) do
    %{
      type: :project,
      id: project.id,
      name: project.name,
      project_slug: project.slug,
      workspace_slug: workspace_by_id[project.workspace_id].slug
    }
  end

  defp entity_destinations(projects_by_id, workspace_by_id, query, limit) do
    # String.length, not byte_size: a single non-ASCII character must not
    # slip past the minimum-length threshold for the cross-project searches.
    if map_size(projects_by_id) == 0 or String.length(query) < @min_entity_query_length do
      []
    else
      run_entity_searches(projects_by_id, workspace_by_id, query, limit)
    end
  end

  defp run_entity_searches(projects_by_id, workspace_by_id, query, limit) do
    project_ids = Map.keys(projects_by_id)
    search_opts = [limit: limit]

    Enum.flat_map(
      [
        {:sheet, Sheets.search_sheets_in_projects(project_ids, query, search_opts)},
        {:flow, Flows.search_flows_in_projects(project_ids, query, search_opts)},
        {:scene, Scenes.search_scenes_in_projects(project_ids, query, search_opts)}
      ],
      fn {type, entities} ->
        Enum.map(entities, fn entity ->
          project = projects_by_id[entity.project_id]

          %{
            type: type,
            id: entity.id,
            name: entity.name,
            shortcut: entity.shortcut,
            project_id: project.id,
            project_name: project.name,
            project_slug: project.slug,
            workspace_slug: workspace_by_id[project.workspace_id].slug
          }
        end)
      end
    )
  end
end
