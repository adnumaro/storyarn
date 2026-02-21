defmodule Storyarn.Flows.FlowCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Collaboration
  alias Storyarn.Flows.{Flow, FlowNode, NodeCrud, TreeOperations}
  alias Storyarn.Localization.TextExtractor
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Shared.MapUtils
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

  @default_search_limit 25

  @doc "Returns the default search limit used by search_flows/3 and search_flows_deep/3."
  def default_search_limit, do: @default_search_limit

  @doc """
  Searches flows by name or shortcut for reference selection.
  Excludes soft-deleted flows.

  ## Options
    - `:limit` - Max results (default #{@default_search_limit})
    - `:offset` - Skip N results (default 0)
    - `:exclude_id` - Flow ID to exclude from results (e.g., current flow)
  """
  def search_flows(project_id, query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, @default_search_limit)
    offset = Keyword.get(opts, :offset, 0)
    exclude_id = Keyword.get(opts, :exclude_id)
    query_str = String.trim(query)

    base =
      from(f in Flow,
        where: f.project_id == ^project_id and is_nil(f.deleted_at)
      )

    base = maybe_exclude_flow(base, exclude_id)

    if query_str == "" do
      from(f in base,
        order_by: [desc: f.updated_at],
        limit: ^limit,
        offset: ^offset
      )
      |> Repo.all()
    else
      search_term = "%#{query_str}%"

      from(f in base,
        where: ilike(f.name, ^search_term) or ilike(f.shortcut, ^search_term),
        order_by: [asc: f.name],
        limit: ^limit,
        offset: ^offset
      )
      |> Repo.all()
    end
  end

  defp maybe_exclude_flow(query, nil), do: query
  defp maybe_exclude_flow(query, id), do: from(f in query, where: f.id != ^id)

  @doc """
  Deep search: searches flow names/shortcuts AND node content (dialogue text,
  labels, technical IDs, hub IDs, expressions, stage directions, menu text, locations).

  Uses JSONB text search on the flow_nodes.data column via a subquery.

  ## Options
    - `:limit` - Max results (default #{@default_search_limit})
    - `:offset` - Skip N results (default 0)
    - `:exclude_id` - Flow ID to exclude from results
  """
  def search_flows_deep(project_id, query, opts \\ []) when is_binary(query) do
    query_str = String.trim(query)

    if query_str == "" do
      search_flows(project_id, query_str, opts)
    else
      limit = Keyword.get(opts, :limit, @default_search_limit)
      offset = Keyword.get(opts, :offset, 0)
      exclude_id = Keyword.get(opts, :exclude_id)
      search_term = "%#{query_str}%"

      from(f in Flow,
        where: f.project_id == ^project_id and is_nil(f.deleted_at),
        where:
          ilike(f.name, ^search_term) or
            ilike(f.shortcut, ^search_term) or
            f.id in subquery(node_content_subquery(project_id, search_term)),
        order_by: [asc: f.name],
        limit: ^limit,
        offset: ^offset
      )
      |> maybe_exclude_flow(exclude_id)
      |> Repo.all()
    end
  end

  # Subquery matching node JSONB data fields against a search term.
  @searchable_jsonb_keys ~w(text label technical_id hub_id expression stage_directions menu_text location)
  defp node_content_subquery(project_id, search_term) do
    conditions =
      Enum.reduce(@searchable_jsonb_keys, dynamic(false), fn key, acc ->
        dynamic([n], ^acc or ilike(fragment("?->>?", n.data, ^key), ^search_term))
      end)

    from(n in FlowNode,
      join: fl in Flow,
      on: n.flow_id == fl.id,
      where: fl.project_id == ^project_id and is_nil(fl.deleted_at) and is_nil(n.deleted_at),
      where: ^conditions,
      select: n.flow_id
    )
  end

  def get_flow(project_id, flow_id) do
    active_nodes_query =
      from(n in FlowNode, where: is_nil(n.deleted_at), order_by: [asc: n.inserted_at])

    from(f in Flow,
      where: f.project_id == ^project_id and f.id == ^flow_id and is_nil(f.deleted_at),
      preload: [:connections, nodes: ^active_nodes_query]
    )
    |> Repo.one()
  end

  @doc """
  Gets a flow with only basic fields (no preloads).
  Used for breadcrumbs and lightweight lookups.
  """
  def get_flow_brief(project_id, flow_id) do
    from(f in Flow,
      where: f.project_id == ^project_id and f.id == ^flow_id and is_nil(f.deleted_at)
    )
    |> Repo.one()
  end

  def get_flow!(project_id, flow_id) do
    active_nodes_query =
      from(n in FlowNode, where: is_nil(n.deleted_at), order_by: [asc: n.inserted_at])

    from(f in Flow,
      where: f.project_id == ^project_id and f.id == ^flow_id and is_nil(f.deleted_at),
      preload: [:connections, nodes: ^active_nodes_query]
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

  @doc """
  Creates a child flow and assigns it to a node's referenced_flow_id.
  Used by exit (flow_reference mode) and subflow nodes.
  Returns `{:ok, %{flow: flow, node: node}}` or `{:error, step, reason, changes}`.
  """
  def create_linked_flow(
        %Project{} = project,
        %Flow{} = parent_flow,
        %FlowNode{} = node,
        opts \\ []
      ) do
    name = opts[:name] || derive_linked_flow_name(parent_flow, node)

    Ecto.Multi.new()
    |> Ecto.Multi.run(:flow, fn _repo, _ ->
      create_flow(project, %{name: name, parent_id: parent_flow.id})
    end)
    |> Ecto.Multi.run(:node, fn _repo, %{flow: new_flow} ->
      new_data = Map.put(node.data, "referenced_flow_id", new_flow.id)

      node
      |> FlowNode.data_changeset(%{data: new_data})
      |> Repo.update()
    end)
    |> Repo.transaction()
  end

  defp derive_linked_flow_name(parent_flow, node) do
    label = node.data["label"]
    if label && label != "", do: label, else: "#{parent_flow.name} - Sub"
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
            data: %{
              "label" => "",
              "technical_id" => "",
              "outcome_tags" => [],
              "outcome_color" => "#22c55e",
              "exit_mode" => "terminal",
              "referenced_flow_id" => nil
            }
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

    result =
      flow
      |> Flow.update_changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, updated_flow} -> TextExtractor.extract_flow(updated_flow)
      _ -> :ok
    end

    result
  end

  @doc """
  Soft-deletes a flow by setting deleted_at.
  Also soft-deletes all children recursively.
  """
  def delete_flow(%Flow{} = flow) do
    result =
      Repo.transaction(fn ->
        # Clean up localization texts
        TextExtractor.delete_flow_texts(flow.id)

        # Soft delete the flow itself
        case flow |> Flow.delete_changeset() |> Repo.update() do
          {:ok, deleted_flow} ->
            # Also soft-delete all children recursively
            soft_delete_children(flow.project_id, flow.id)
            deleted_flow

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)

    # Notify open canvases that have subflow nodes referencing this flow
    case result do
      {:ok, _} -> notify_affected_subflows(flow.id, flow.project_id)
      _ -> :ok
    end

    result
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

  defp notify_affected_subflows(deleted_flow_id, project_id) do
    affected = NodeCrud.list_subflow_nodes_referencing(deleted_flow_id, project_id)

    affected
    |> Enum.map(& &1.flow_id)
    |> Enum.uniq()
    |> Enum.each(fn flow_id ->
      Collaboration.broadcast_change(flow_id, :flow_refresh, %{
        user_id: 0,
        user_email: "System",
        user_color: "#666"
      })
    end)
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
      TextExtractor.delete_flow_texts(child.id)

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

    cond do
      # If attrs explicitly set shortcut, use that
      Map.has_key?(attrs, "shortcut") ->
        attrs

      # If name is changing, regenerate shortcut from new name
      name_changing?(attrs, flow) ->
        shortcut = Shortcuts.generate_flow_shortcut(attrs["name"], flow.project_id, flow.id)
        Map.put(attrs, "shortcut", shortcut)

      # If flow has no shortcut yet, generate one from current name
      missing_shortcut?(flow) ->
        generate_shortcut_from_current_name(flow, attrs)

      true ->
        attrs
    end
  end

  defp name_changing?(attrs, flow) do
    new_name = attrs["name"]
    new_name && new_name != "" && new_name != flow.name
  end

  defp missing_shortcut?(flow) do
    is_nil(flow.shortcut) || flow.shortcut == ""
  end

  defp generate_shortcut_from_current_name(flow, attrs) do
    name = flow.name

    if name && name != "" do
      shortcut = Shortcuts.generate_flow_shortcut(name, flow.project_id, flow.id)
      Map.put(attrs, "shortcut", shortcut)
    else
      attrs
    end
  end

  defp stringify_keys(map), do: MapUtils.stringify_keys(map)

  defp maybe_assign_position(attrs, project_id, parent_id) do
    if Map.has_key?(attrs, "position") do
      attrs
    else
      position = TreeOperations.next_position(project_id, parent_id)
      Map.put(attrs, "position", position)
    end
  end
end
