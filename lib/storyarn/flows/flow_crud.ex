defmodule Storyarn.Flows.FlowCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Flow
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Shortcuts

  def list_flows(project_id) do
    from(f in Flow,
      where: f.project_id == ^project_id,
      order_by: [desc: f.is_main, asc: f.name]
    )
    |> Repo.all()
  end

  @doc """
  Searches flows by name or shortcut for reference selection.
  Returns flows matching the query, limited to 10 results.
  """
  def search_flows(project_id, query) when is_binary(query) do
    query = String.trim(query)

    if query == "" do
      # Return recent flows if no query
      from(f in Flow,
        where: f.project_id == ^project_id,
        order_by: [desc: f.updated_at],
        limit: 10
      )
      |> Repo.all()
    else
      search_term = "%#{query}%"

      from(f in Flow,
        where: f.project_id == ^project_id,
        where: ilike(f.name, ^search_term) or ilike(f.shortcut, ^search_term),
        order_by: [asc: f.name],
        limit: 10
      )
      |> Repo.all()
    end
  end

  def get_flow(project_id, flow_id) do
    Flow
    |> where(project_id: ^project_id, id: ^flow_id)
    |> preload([:nodes, :connections])
    |> Repo.one()
  end

  def get_flow!(project_id, flow_id) do
    Flow
    |> where(project_id: ^project_id, id: ^flow_id)
    |> preload([:nodes, :connections])
    |> Repo.one!()
  end

  def create_flow(%Project{} = project, attrs) do
    # Auto-generate shortcut from name if not provided
    attrs = maybe_generate_shortcut(attrs, project.id, nil)

    %Flow{project_id: project.id}
    |> Flow.create_changeset(attrs)
    |> Repo.insert()
  end

  def update_flow(%Flow{} = flow, attrs) do
    # Auto-generate shortcut if flow has no shortcut and name is being updated
    attrs = maybe_generate_shortcut_on_update(flow, attrs)

    flow
    |> Flow.update_changeset(attrs)
    |> Repo.update()
  end

  def delete_flow(%Flow{} = flow) do
    Repo.delete(flow)
  end

  def change_flow(%Flow{} = flow, attrs \\ %{}) do
    Flow.update_changeset(flow, attrs)
  end

  def get_main_flow(project_id) do
    Flow
    |> where(project_id: ^project_id, is_main: true)
    |> Repo.one()
  end

  def set_main_flow(%Flow{} = flow) do
    Repo.transaction(fn ->
      from(f in Flow, where: f.project_id == ^flow.project_id and f.is_main == true)
      |> Repo.update_all(set: [is_main: false])

      flow
      |> Ecto.Changeset.change(is_main: true)
      |> Repo.update!()
    end)
  end

  defp maybe_generate_shortcut(attrs, project_id, exclude_flow_id) do
    attrs = stringify_keys(attrs)
    has_shortcut = Map.has_key?(attrs, "shortcut")
    name = attrs["name"]

    if has_shortcut || is_nil(name) || name == "" do
      attrs
    else
      shortcut = Shortcuts.generate_flow_shortcut(name, project_id, exclude_flow_id)
      Map.put(attrs, "shortcut", shortcut)
    end
  end

  defp maybe_generate_shortcut_on_update(%Flow{} = flow, attrs) do
    attrs = stringify_keys(attrs)

    # If attrs explicitly set shortcut, use that
    if Map.has_key?(attrs, "shortcut") do
      attrs
    else
      # If name is changing, regenerate shortcut from new name
      new_name = attrs["name"]

      if new_name && new_name != "" && new_name != flow.name do
        shortcut = Shortcuts.generate_flow_shortcut(new_name, flow.project_id, flow.id)
        Map.put(attrs, "shortcut", shortcut)
      else
        # If flow has no shortcut yet, generate one from current name
        if is_nil(flow.shortcut) || flow.shortcut == "" do
          name = flow.name

          if name && name != "" do
            shortcut = Shortcuts.generate_flow_shortcut(name, flow.project_id, flow.id)
            Map.put(attrs, "shortcut", shortcut)
          else
            attrs
          end
        else
          attrs
        end
      end
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
