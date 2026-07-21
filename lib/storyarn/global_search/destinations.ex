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
    query = query |> to_string() |> String.slice(0, @max_query_length) |> String.trim()

    workspace_entries = Workspaces.list_workspaces(scope)
    workspace_by_id = Map.new(workspace_entries, fn %{workspace: w} -> {w.id, w} end)

    project_entries =
      workspace_entries
      |> Enum.flat_map(fn %{workspace: workspace} ->
        Projects.list_projects_for_workspace(workspace.id, scope)
      end)
      |> Enum.uniq_by(& &1.project.id)

    projects_by_id = Map.new(project_entries, fn %{project: p} -> {p.id, p} end)

    %{
      workspaces:
        workspace_entries
        |> Enum.map(& &1.workspace)
        |> filter_by_name(query)
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

  defp filter_by_name(items, ""), do: items

  defp filter_by_name(items, query) do
    downcased = String.downcase(query)
    Enum.filter(items, &String.contains?(String.downcase(&1.name), downcased))
  end

  defp workspace_destination(workspace) do
    %{type: :workspace, id: workspace.id, name: workspace.name, workspace_slug: workspace.slug}
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

  defp entity_destinations(projects_by_id, _workspace_by_id, query, _limit)
       when map_size(projects_by_id) == 0 or byte_size(query) < @min_entity_query_length, do: []

  defp entity_destinations(projects_by_id, workspace_by_id, query, limit) do
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
            project_name: project.name,
            project_slug: project.slug,
            workspace_slug: workspace_by_id[project.workspace_id].slug
          }
        end)
      end
    )
  end
end
