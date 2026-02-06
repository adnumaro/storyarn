defmodule Storyarn.Flows.FlowCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.{Flow, FlowNode, TreeOperations}
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Shortcuts

  @doc """
  Lists all non-deleted flows for a project.
  Returns flows ordered by is_main (descending) then name.
  """
  def list_flows(project_id) do
    from(f in Flow,
      where: f.project_id == ^project_id and is_nil(f.deleted_at),
      order_by: [desc: f.is_main, asc: f.name]
    )
    |> Repo.all()
  end

  @doc """
  Lists flows as a tree structure.
  Returns root-level flows with their children preloaded (up to 5 levels deep).
  """
  def list_flows_tree(project_id) do
    # Load all non-deleted flows for the project
    all_flows =
      from(f in Flow,
        where: f.project_id == ^project_id and is_nil(f.deleted_at),
        order_by: [asc: f.position, asc: f.name]
      )
      |> Repo.all()

    # Build tree structure in memory
    build_tree(all_flows, nil)
  end

  @doc """
  Lists flows by parent (for tree navigation).
  Use parent_id = nil for root level flows.
  """
  def list_flows_by_parent(project_id, parent_id) do
    TreeOperations.list_flows_by_parent(project_id, parent_id)
  end

  defp build_tree(all_flows, parent_id) do
    all_flows
    |> Enum.filter(&(&1.parent_id == parent_id))
    |> Enum.map(fn flow ->
      children = build_tree(all_flows, flow.id)
      %{flow | children: children}
    end)
  end

  @doc """
  Searches flows by name or shortcut for reference selection.
  Returns flows matching the query, limited to 10 results.
  Excludes soft-deleted flows.
  """
  def search_flows(project_id, query) when is_binary(query) do
    query = String.trim(query)

    if query == "" do
      # Return recent flows if no query
      from(f in Flow,
        where: f.project_id == ^project_id and is_nil(f.deleted_at),
        order_by: [desc: f.updated_at],
        limit: 10
      )
      |> Repo.all()
    else
      search_term = "%#{query}%"

      from(f in Flow,
        where: f.project_id == ^project_id and is_nil(f.deleted_at),
        where: ilike(f.name, ^search_term) or ilike(f.shortcut, ^search_term),
        order_by: [asc: f.name],
        limit: 10
      )
      |> Repo.all()
    end
  end

  def get_flow(project_id, flow_id) do
    from(f in Flow,
      where: f.project_id == ^project_id and f.id == ^flow_id and is_nil(f.deleted_at),
      preload: [:nodes, :connections]
    )
    |> Repo.one()
  end

  def get_flow!(project_id, flow_id) do
    from(f in Flow,
      where: f.project_id == ^project_id and f.id == ^flow_id and is_nil(f.deleted_at),
      preload: [:nodes, :connections]
    )
    |> Repo.one!()
  end

  @doc """
  Gets a flow including soft-deleted ones (for trash/restore).
  """
  def get_flow_including_deleted(project_id, flow_id) do
    from(f in Flow,
      where: f.project_id == ^project_id and f.id == ^flow_id,
      preload: [:nodes, :connections]
    )
    |> Repo.one()
  end

  def create_flow(%Project{} = project, attrs) do
    attrs = stringify_keys(attrs)

    # Auto-generate shortcut from name if not provided
    attrs = maybe_generate_shortcut(attrs, project.id, nil)

    # Auto-assign position if not provided
    parent_id = attrs["parent_id"]
    attrs = maybe_assign_position(attrs, project.id, parent_id)

    Repo.transaction(fn ->
      case %Flow{project_id: project.id}
           |> Flow.create_changeset(attrs)
           |> Repo.insert() do
        {:ok, flow} ->
          # Auto-create Entry node at position {100, 300}
          %FlowNode{flow_id: flow.id}
          |> FlowNode.create_changeset(%{
            type: "entry",
            position_x: 100.0,
            position_y: 300.0,
            data: %{}
          })
          |> Repo.insert!()

          # Auto-create Exit node at position {500, 300}
          %FlowNode{flow_id: flow.id}
          |> FlowNode.create_changeset(%{
            type: "exit",
            position_x: 500.0,
            position_y: 300.0,
            data: %{"label" => "", "technical_id" => "", "is_success" => true}
          })
          |> Repo.insert!()

          flow

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  def update_flow(%Flow{} = flow, attrs) do
    # Auto-generate shortcut if flow has no shortcut and name is being updated
    attrs = maybe_generate_shortcut_on_update(flow, attrs)

    flow
    |> Flow.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Soft-deletes a flow by setting deleted_at.
  Also soft-deletes all children recursively.
  """
  def delete_flow(%Flow{} = flow) do
    Repo.transaction(fn ->
      # Soft delete the flow itself
      {:ok, deleted_flow} =
        flow
        |> Flow.delete_changeset()
        |> Repo.update()

      # Also soft-delete all children recursively
      soft_delete_children(flow.project_id, flow.id)

      deleted_flow
    end)
  end

  @doc """
  Permanently deletes a flow from the database.
  Use with caution - this cannot be undone.
  """
  def hard_delete_flow(%Flow{} = flow) do
    Repo.delete(flow)
  end

  @doc """
  Restores a soft-deleted flow.
  """
  def restore_flow(%Flow{} = flow) do
    flow
    |> Flow.restore_changeset()
    |> Repo.update()
  end

  @doc """
  Lists all soft-deleted flows for a project (trash).
  """
  def list_deleted_flows(project_id) do
    from(f in Flow,
      where: f.project_id == ^project_id and not is_nil(f.deleted_at),
      order_by: [desc: f.deleted_at]
    )
    |> Repo.all()
  end

  defp soft_delete_children(project_id, parent_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Get all children
    children =
      from(f in Flow,
        where: f.project_id == ^project_id and f.parent_id == ^parent_id and is_nil(f.deleted_at)
      )
      |> Repo.all()

    # Soft delete each child and recursively delete their children
    Enum.each(children, fn child ->
      from(f in Flow, where: f.id == ^child.id)
      |> Repo.update_all(set: [deleted_at: now])

      # Always recurse - any flow can have children
      soft_delete_children(project_id, child.id)
    end)
  end

  def change_flow(%Flow{} = flow, attrs \\ %{}) do
    Flow.update_changeset(flow, attrs)
  end

  def get_main_flow(project_id) do
    from(f in Flow,
      where: f.project_id == ^project_id and f.is_main == true and is_nil(f.deleted_at)
    )
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

  defp maybe_assign_position(attrs, project_id, parent_id) do
    if Map.has_key?(attrs, "position") do
      attrs
    else
      position = TreeOperations.next_position(project_id, parent_id)
      Map.put(attrs, "position", position)
    end
  end
end
