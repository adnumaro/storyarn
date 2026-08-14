defmodule Storyarn.Sheets.ReferenceTracker do
  @moduledoc """
  Tracks entity references between sheets, flows, and blocks.

  This module provides functions to:
  - Extract references from rich_text content (mentions)
  - Extract references from reference blocks
  - Update references atomically when content changes
  - Query backlinks for a given target

  ## Reference Lifecycle

  - References are created when blocks are saved (reference blocks, rich_text with mentions)
  - References are updated atomically when block content changes
  - References are deleted when source blocks are deleted

  ## Edge Cases

  - **Deleted sources**: References from soft-deleted blocks/sheets are excluded from backlinks
  - **Deleted targets**: References to deleted targets show "not found" in UI
  - **Orphaned references**: References from deleted sources are cleaned up during bulk deletions
  - **Cross-project**: References are always scoped to a single project

  ## Performance

  - Backlinks query is optimized with JOINs (no N+1)
  - Indexes exist on (source_type, source_id) and (target_type, target_id)
  """

  import Ecto.Query

  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.References.ProjectReferenceIntegrity
  alias Storyarn.References.RichTextMentions
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.EntityReference
  alias Storyarn.Sheets.Sheet

  @project_target_types %{
    "block" => ~w(sheet flow),
    "flow_node" => ~w(sheet flow),
    "scene_pin" => ~w(sheet flow),
    "scene_zone" => ~w(sheet flow scene)
  }

  @doc """
  Updates references from a block.

  Deletes all existing references from this block and creates new ones
  based on the current block state.
  """
  @spec update_block_references(map(), keyword()) :: :ok | {:error, term()}
  def update_block_references(block, opts \\ []) do
    block_id = block.id

    operation = fn ->
      # Delete existing references from this block
      Repo.delete_all(from(r in EntityReference, where: r.source_type == "block" and r.source_id == ^block_id))

      # Extract and batch-insert new references
      references = extract_block_references(block)
      batch_insert_references("block", block_id, references, opts)
    end

    if Repo.in_transaction?() do
      operation.()
    else
      case Repo.transaction(operation) do
        {:ok, :ok} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Validates the entity references encoded in a prospective block value.

  This is a writer guard, not a tracker repair operation. It must run in the
  same transaction as the block write so every target stays active and in the
  source project until commit.
  """
  @spec lock_and_normalize_block_value(integer(), String.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def lock_and_normalize_block_value(project_id, "reference", value) when is_integer(project_id) and is_map(value) do
    case extract_block_value_references("reference", value) do
      {:ok, []} ->
        clear_reference_target(value)

      {:ok, [%{type: type, id: id}]} ->
        lock_reference_target(project_id, value, type, id)

      {:error, _reason} = error ->
        error
    end
  end

  def lock_and_normalize_block_value(project_id, "rich_text", value) when is_integer(project_id) and is_map(value) do
    content = value["content"] || value[:content] || ""

    with {:ok, references} <- extract_block_value_references("rich_text", value),
         specs = Enum.map(references, &mention_reference_spec/1),
         {:ok, _normalized_ids} <-
           ProjectReferenceIntegrity.lock_active_references(project_id, specs) do
      {:ok,
       value
       |> Map.delete(:content)
       |> Map.put("content", content)}
    end
  end

  def lock_and_normalize_block_value(_project_id, type, value) when type in ["reference", "rich_text"] do
    {:error, {:invalid_project_reference, {:block, :value, type}, value}}
  end

  def lock_and_normalize_block_value(_project_id, _type, value), do: {:ok, value}

  @doc """
  Extracts the project entity references encoded in a prospective block value.

  Unlike the best-effort extraction used to repair historical tracker rows,
  this function applies the same strict value contract as the writer guard so
  restore previews can surface malformed references instead of omitting them.
  """
  @spec extract_block_value_references(String.t(), term()) ::
          {:ok, [map()]} | {:error, term()}
  def extract_block_value_references("reference", value) when is_map(value) do
    target_type = reference_value(value, "target_type")
    target_id = reference_value(value, "target_id")

    case {normalize_optional_target_type(target_type), target_id} do
      {nil, id} when id in [nil, ""] ->
        {:ok, []}

      {type, id} when type in ["sheet", "flow"] and id not in [nil, ""] ->
        validate_block_reference(type, id, target_type)

      _invalid_pair ->
        {:error, {:invalid_project_reference, {:block, :value, target_type}, target_id}}
    end
  end

  def extract_block_value_references("rich_text", value) when is_map(value) do
    content = value["content"] || value[:content] || ""
    strict_mentions_from_html(content)
  end

  def extract_block_value_references(type, value) when type in ["reference", "rich_text"] do
    {:error, {:invalid_project_reference, {:block, :value, type}, value}}
  end

  def extract_block_value_references(_type, _value), do: {:ok, []}

  defp validate_block_reference(type, id, diagnostic_type) do
    case ProjectReferenceIntegrity.normalize_optional_id(id) do
      {:ok, normalized_id} when is_integer(normalized_id) ->
        {:ok, [%{type: type, id: id, context: "value"}]}

      _invalid_or_absent ->
        {:error, {:invalid_project_reference, {:block, :value, diagnostic_type}, id}}
    end
  end

  defp clear_reference_target(value) do
    {:ok,
     value
     |> put_reference_value("target_type", nil)
     |> put_reference_value("target_id", nil)}
  end

  defp lock_reference_target(project_id, value, type, id) do
    reference_type = if(type == "sheet", do: :sheet, else: :flow)
    context = {:block, :value, type}

    case ProjectReferenceIntegrity.lock_active_references(project_id, [
           {reference_type, context, id}
         ]) do
      {:ok, [normalized_id]} ->
        {:ok,
         value
         |> put_reference_value("target_type", type)
         |> put_reference_value("target_id", normalized_id)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes all references from a block.
  Called when a block is deleted.
  """
  @spec delete_block_references(any()) :: {integer(), nil}
  def delete_block_references(block_id) do
    Repo.delete_all(from(r in EntityReference, where: r.source_type == "block" and r.source_id == ^block_id))
  end

  @doc """
  Updates references for a flow node based on its data.
  Extracts mentions from rich text fields and speaker references.
  """
  @spec update_flow_node_references(map(), keyword()) :: :ok | {:error, term()}
  def update_flow_node_references(node, opts \\ [])

  def update_flow_node_references(%{id: node_id, data: data}, opts) when is_map(data) do
    with :ok <- validate_project_id_option(opts) do
      run_reference_update(fn -> replace_flow_node_references(node_id, opts) end)
    end
  end

  def update_flow_node_references(_node, _opts), do: :ok

  @doc false
  @spec flow_node_references_current?(map()) :: boolean()
  def flow_node_references_current?(%{id: node_id, data: data}) when is_integer(node_id) and is_map(data) do
    node_id in flow_node_references_current_ids([%{id: node_id, data: data}])
  end

  def flow_node_references_current?(_node), do: false

  @doc false
  @spec flow_node_references_current_ids([map()]) :: MapSet.t(integer())
  def flow_node_references_current_ids(nodes) when is_list(nodes) do
    valid_nodes =
      Enum.filter(nodes, fn
        %{id: node_id, data: data} when is_integer(node_id) and is_map(data) -> true
        _node -> false
      end)

    node_ids = Enum.map(valid_nodes, & &1.id)
    actual_by_node = flow_node_reference_sets(node_ids)

    Enum.reduce(valid_nodes, MapSet.new(), fn node, current_ids ->
      expected = expected_flow_node_reference_set(node.data)
      actual = Map.get(actual_by_node, node.id, MapSet.new())

      if expected == actual,
        do: MapSet.put(current_ids, node.id),
        else: current_ids
    end)
  end

  defp flow_node_reference_sets([]), do: %{}

  defp flow_node_reference_sets(node_ids) do
    from(reference in EntityReference,
      where:
        reference.source_type == "flow_node" and
          reference.source_id in ^node_ids,
      select: {
        reference.source_id,
        reference.target_type,
        reference.target_id,
        reference.context
      }
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {source_id, target_type, target_id, context}, references ->
      reference = {target_type, target_id, context}
      Map.update(references, source_id, MapSet.new([reference]), &MapSet.put(&1, reference))
    end)
  end

  defp expected_flow_node_reference_set(data) do
    data
    |> extract_flow_node_refs()
    |> Enum.map(fn reference ->
      {reference.type, parse_id(reference.id), reference.context}
    end)
    |> Enum.reject(fn {_type, target_id, _context} -> is_nil(target_id) end)
    |> MapSet.new()
  end

  @doc """
  Deletes all references from a flow node.
  Called when a node is deleted.
  """
  @spec delete_flow_node_references(any()) :: {integer(), nil}
  def delete_flow_node_references(node_id) do
    Repo.delete_all(from(r in EntityReference, where: r.source_type == "flow_node" and r.source_id == ^node_id))
  end

  @doc """
  Gets all references pointing to a target (backlinks).

  Returns references grouped by source type with additional context.
  """
  @spec get_backlinks(String.t(), any()) :: [map()]
  def get_backlinks(target_type, target_id) do
    Repo.all(
      from(r in EntityReference,
        where: r.target_type == ^target_type and r.target_id == ^target_id,
        order_by: [desc: r.inserted_at]
      )
    )
  end

  @doc """
  Returns active block IDs whose tracked entity reference points to a missing,
  deleted, or cross-project sheet/flow target.

  The batch query is used by sheet health checks to avoid resolving every
  rich-text mention and reference block independently.
  """
  @spec list_stale_block_reference_source_ids(integer(), [integer()]) :: MapSet.t()
  def list_stale_block_reference_source_ids(_project_id, []), do: MapSet.new()

  def list_stale_block_reference_source_ids(project_id, block_ids) do
    project_id
    |> stale_block_reference_query(block_ids)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc "Resolves active sheet and flow targets in a fixed number of queries."
  @spec get_reference_targets([{String.t() | nil, integer() | nil}], integer()) :: map()
  def get_reference_targets(references, project_id) when is_list(references) do
    sheet_ids = reference_target_ids(references, "sheet")
    flow_ids = reference_target_ids(references, "flow")

    sheet_targets =
      Repo.all(
        from(sheet in Sheet,
          where:
            sheet.project_id == ^project_id and sheet.id in ^sheet_ids and
              is_nil(sheet.deleted_at),
          select: %{
            type: "sheet",
            id: sheet.id,
            name: sheet.name,
            shortcut: sheet.shortcut
          }
        )
      )

    flow_targets =
      Repo.all(
        from(flow in Flow,
          where:
            flow.project_id == ^project_id and flow.id in ^flow_ids and
              is_nil(flow.deleted_at),
          select: %{
            type: "flow",
            id: flow.id,
            name: flow.name,
            shortcut: flow.shortcut
          }
        )
      )

    Map.new(sheet_targets ++ flow_targets, &{{&1.type, &1.id}, &1})
  end

  defp reference_target_ids(references, target_type) do
    references
    |> Enum.flat_map(fn
      {^target_type, target_id} when is_integer(target_id) and target_id > 0 -> [target_id]
      _reference -> []
    end)
    |> Enum.uniq()
  end

  defp stale_block_reference_query(project_id, block_ids) do
    EntityReference
    |> join_block_reference_sources(project_id, block_ids)
    |> join_block_reference_targets(project_id)
    |> filter_stale_block_reference_targets()
    |> distinct(true)
    |> select([source_block: source_block], source_block.id)
  end

  defp join_block_reference_sources(query, project_id, block_ids) do
    from(reference in query,
      as: :reference,
      join: source_block in Block,
      as: :source_block,
      on: reference.source_type == "block" and reference.source_id == source_block.id,
      join: source_sheet in Sheet,
      as: :source_sheet,
      on: source_sheet.id == source_block.sheet_id,
      where:
        source_block.id in ^block_ids and source_sheet.project_id == ^project_id and
          is_nil(source_block.deleted_at) and is_nil(source_sheet.deleted_at)
    )
  end

  defp join_block_reference_targets(query, project_id) do
    from([reference: reference] in query,
      left_join: target_sheet in Sheet,
      as: :target_sheet,
      on:
        reference.target_type == "sheet" and reference.target_id == target_sheet.id and
          target_sheet.project_id == ^project_id and is_nil(target_sheet.deleted_at),
      left_join: target_flow in Flow,
      as: :target_flow,
      on:
        reference.target_type == "flow" and reference.target_id == target_flow.id and
          target_flow.project_id == ^project_id and is_nil(target_flow.deleted_at)
    )
  end

  defp filter_stale_block_reference_targets(query) do
    from(
      [reference: reference, target_sheet: target_sheet, target_flow: target_flow] in query,
      where:
        (reference.target_type == "sheet" and is_nil(target_sheet.id)) or
          (reference.target_type == "flow" and is_nil(target_flow.id))
    )
  end

  @doc """
  Gets backlinks with preloaded source information.

  Returns a list of maps with:
  - source_type, source_id
  - target_type, target_id
  - context
  - source_name (resolved name of the source)
  - source_parent (sheet/flow that contains the source)

  Optimized to use JOINs instead of N+1 queries.
  """
  @spec get_backlinks_with_sources(String.t(), any(), integer()) :: [map()]
  def get_backlinks_with_sources(target_type, target_id, project_id) do
    block_backlinks = query_block_backlinks(target_type, target_id, project_id)
    flow_backlinks = query_flow_node_backlinks(target_type, target_id, project_id)
    map_pin_backlinks = query_scene_pin_backlinks(target_type, target_id, project_id)
    map_zone_backlinks = query_scene_zone_backlinks(target_type, target_id, project_id)

    Enum.sort_by(
      block_backlinks ++ flow_backlinks ++ map_pin_backlinks ++ map_zone_backlinks,
      & &1.inserted_at,
      {:desc, NaiveDateTime}
    )
  end

  defp query_block_backlinks(target_type, target_id, project_id) do
    from(r in EntityReference,
      join: b in Block,
      on: r.source_type == "block" and r.source_id == b.id,
      join: s in Sheet,
      on: b.sheet_id == s.id,
      where: r.target_type == ^target_type and r.target_id == ^target_id,
      where: s.project_id == ^project_id and is_nil(s.deleted_at) and is_nil(b.deleted_at),
      select: %{
        id: r.id,
        source_type: r.source_type,
        source_id: r.source_id,
        context: r.context,
        inserted_at: r.inserted_at,
        block_type: b.type,
        block_label: fragment("?->>'label'", b.config),
        sheet_id: s.id,
        sheet_name: s.name,
        sheet_shortcut: s.shortcut
      },
      order_by: [desc: r.inserted_at]
    )
    |> Repo.all()
    |> Enum.map(fn ref ->
      %{
        id: ref.id,
        source_type: "block",
        source_id: ref.source_id,
        context: ref.context,
        inserted_at: ref.inserted_at,
        source_info: %{
          type: :sheet,
          sheet_id: ref.sheet_id,
          sheet_name: ref.sheet_name,
          sheet_shortcut: ref.sheet_shortcut,
          block_type: ref.block_type,
          block_label: ref.block_label
        }
      }
    end)
  end

  defp query_flow_node_backlinks(target_type, target_id, project_id) do
    Storyarn.Flows.query_flow_node_backlinks(target_type, target_id, project_id)
  end

  @doc """
  Counts backlinks for a target.
  """
  @spec count_backlinks(String.t(), any()) :: integer()
  def count_backlinks(target_type, target_id) do
    Repo.one(
      from(r in EntityReference,
        where: r.target_type == ^target_type and r.target_id == ^target_id,
        select: count(r.id)
      )
    )
  end

  # ---------------------------------------------------------------------------
  # Map element references (pins & zones)
  # ---------------------------------------------------------------------------

  @doc """
  Updates references from a map pin.
  Tracks target_type/target_id and sheet_id references.
  """
  @spec update_scene_pin_references(map(), keyword()) :: :ok
  def update_scene_pin_references(pin, opts \\ [])

  def update_scene_pin_references(%{id: pin_id} = pin, opts) do
    delete_map_pin_references(pin_id)

    refs = extract_map_pin_refs(pin)
    batch_insert_references("scene_pin", pin_id, refs, opts)
  end

  def update_scene_pin_references(_pin, _opts), do: :ok

  @doc """
  Deletes all references from a map pin.
  """
  @spec delete_map_pin_references(any()) :: {integer(), nil}
  def delete_map_pin_references(pin_id) do
    Repo.delete_all(from(r in EntityReference, where: r.source_type == "scene_pin" and r.source_id == ^pin_id))
  end

  @doc """
  Updates references from a map zone.
  Tracks target_type/target_id references.
  """
  @spec update_scene_zone_references(map(), keyword()) :: :ok
  def update_scene_zone_references(zone, opts \\ [])

  def update_scene_zone_references(%{id: zone_id} = zone, opts) do
    delete_map_zone_references(zone_id)

    refs = extract_map_zone_refs(zone)
    batch_insert_references("scene_zone", zone_id, refs, opts)
  end

  def update_scene_zone_references(_zone, _opts), do: :ok

  @doc """
  Deletes all references from a map zone.
  """
  @spec delete_map_zone_references(any()) :: {integer(), nil}
  def delete_map_zone_references(zone_id) do
    Repo.delete_all(from(r in EntityReference, where: r.source_type == "scene_zone" and r.source_id == ^zone_id))
  end

  @doc """
  Deletes references pointing to a target unless they originate from a live
  block. Those rows are retained so health checks can report the now-missing
  target in rich-text mentions and reference blocks.
  """
  @spec delete_target_references(String.t(), any()) :: {integer(), nil}
  def delete_target_references(target_type, target_id) do
    retained_blocks_query =
      from(reference in EntityReference,
        join: block in Block,
        on: reference.source_type == "block" and reference.source_id == block.id,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where:
          reference.target_type == ^target_type and reference.target_id == ^target_id and
            is_nil(block.deleted_at) and is_nil(sheet.deleted_at),
        distinct: block.id,
        select: block.id
      )

    retained_blocks_query =
      if target_type == "sheet" do
        from([_reference, block, _sheet] in retained_blocks_query,
          where: block.sheet_id != ^target_id
        )
      else
        retained_blocks_query
      end

    retained_block_ids = Repo.all(retained_blocks_query)

    query =
      from(reference in EntityReference,
        where: reference.target_type == ^target_type and reference.target_id == ^target_id
      )

    query =
      if retained_block_ids == [] do
        query
      else
        from(reference in query,
          where:
            reference.source_type != "block" or
              reference.source_id not in ^retained_block_ids
        )
      end

    Repo.delete_all(query)
  end

  defp query_scene_pin_backlinks(target_type, target_id, project_id) do
    Storyarn.Scenes.query_scene_pin_backlinks(target_type, target_id, project_id)
  end

  defp query_scene_zone_backlinks(target_type, target_id, project_id) do
    Storyarn.Scenes.query_scene_zone_backlinks(target_type, target_id, project_id)
  end

  # Private functions

  defp batch_insert_references(source_type, source_id, references, opts) do
    now = DateTime.to_naive(TimeHelpers.now())

    entries =
      references
      |> Enum.map(fn ref -> ref.id |> parse_id() |> then(&{&1, ref}) end)
      |> Enum.reject(fn {target_id, _} -> is_nil(target_id) end)
      |> Enum.map(fn {target_id, ref} ->
        %{
          source_type: source_type,
          source_id: source_id,
          target_type: ref.type,
          target_id: target_id,
          context: ref.context,
          inserted_at: now,
          updated_at: now
        }
      end)
      |> filter_project_targets(source_type, Keyword.get(opts, :project_id))

    if entries != [], do: Repo.insert_all(EntityReference, entries, on_conflict: :nothing)

    :ok
  end

  defp validate_project_id_option(opts) do
    case Keyword.fetch(opts, :project_id) do
      :error -> :ok
      {:ok, project_id} when is_integer(project_id) and project_id > 0 -> :ok
      {:ok, project_id} -> {:error, {:invalid_project_id, project_id}}
    end
  end

  defp resolve_flow_node_project(node_id, requested_project_id) when is_integer(node_id) do
    source_identity =
      Repo.one(
        from node in FlowNode,
          join: flow in Flow,
          on: flow.id == node.flow_id,
          where: node.id == ^node_id,
          select: {node.flow_id, flow.project_id}
      )

    case source_identity do
      {flow_id, project_id}
      when is_nil(requested_project_id) or project_id == requested_project_id ->
        lock_active_flow_node(node_id, flow_id, project_id, requested_project_id)

      _missing_or_mismatched ->
        flow_node_project_mismatch(node_id, requested_project_id)
    end
  end

  defp resolve_flow_node_project(node_id, requested_project_id),
    do: flow_node_project_mismatch(node_id, requested_project_id)

  defp lock_active_flow_node(node_id, flow_id, project_id, requested_project_id) do
    with {:ok, _project} <- ProjectReferenceIntegrity.lock_active_project(project_id),
         %Flow{} <-
           Repo.one(
             from flow in Flow,
               where:
                 flow.id == ^flow_id and flow.project_id == ^project_id and
                   is_nil(flow.deleted_at),
               lock: "FOR SHARE"
           ),
         %FlowNode{} = node <-
           Repo.one(
             from current_node in FlowNode,
               where:
                 current_node.id == ^node_id and current_node.flow_id == ^flow_id and
                   is_nil(current_node.deleted_at),
               lock: "FOR SHARE"
           ) do
      {:ok, {node, project_id}}
    else
      _inactive_or_missing -> flow_node_project_mismatch(node_id, requested_project_id)
    end
  end

  defp flow_node_project_mismatch(node_id, requested_project_id),
    do: {:error, {:flow_node_project_mismatch, node_id, requested_project_id}}

  defp do_replace_flow_node_references(node_id, data, opts) do
    delete_flow_node_references(node_id)
    references = extract_flow_node_refs(data)
    batch_insert_references("flow_node", node_id, references, opts)
  end

  defp replace_flow_node_references(node_id, opts) do
    requested_project_id = Keyword.get(opts, :project_id)

    with {:ok, {%FlowNode{data: data}, project_id}} <-
           resolve_flow_node_project(node_id, requested_project_id) do
      do_replace_flow_node_references(
        node_id,
        data,
        Keyword.put(opts, :project_id, project_id)
      )
    end
  end

  defp run_reference_update(operation) do
    if Repo.in_transaction?() do
      operation.()
    else
      run_reference_update_transaction(operation)
    end
  end

  defp run_reference_update_transaction(operation) do
    case Repo.transaction(fn -> execute_reference_update!(operation) end) do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_reference_update!(operation) do
    case operation.() do
      :ok -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp filter_project_targets(entries, _source_type, nil), do: entries

  defp filter_project_targets(entries, source_type, project_id) when is_integer(project_id) do
    if not Repo.in_transaction?() do
      raise ArgumentError,
            "project-scoped entity references must be rebuilt inside an explicit database transaction"
    end

    allowed_types = Map.fetch!(@project_target_types, source_type)
    entries = Enum.filter(entries, &(&1.target_type in allowed_types))

    allowed_targets =
      Enum.reduce([{"sheet", Sheet}, {"flow", Flow}, {"scene", Scene}], MapSet.new(), fn {target_type, schema}, allowed ->
        target_ids =
          entries
          |> Enum.filter(&(&1.target_type == target_type))
          |> Enum.map(& &1.target_id)
          |> Enum.uniq()

        active_ids =
          if target_ids == [] do
            []
          else
            Repo.all(
              from target in schema,
                where:
                  target.id in ^target_ids and target.project_id == ^project_id and
                    is_nil(target.deleted_at),
                order_by: [asc: target.id],
                lock: "FOR SHARE",
                select: target.id
            )
          end

        Enum.reduce(active_ids, allowed, &MapSet.put(&2, {target_type, &1}))
      end)

    Enum.filter(entries, &MapSet.member?(allowed_targets, {&1.target_type, &1.target_id}))
  end

  defp filter_project_targets(_entries, _source_type, project_id) do
    raise ArgumentError, "expected :project_id to be an integer, got: #{inspect(project_id)}"
  end

  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_id(_), do: nil

  defp normalize_optional_target_type(nil), do: nil
  defp normalize_optional_target_type(""), do: nil
  defp normalize_optional_target_type(type) when is_atom(type), do: Atom.to_string(type)
  defp normalize_optional_target_type(type), do: type

  defp reference_value(value, key) do
    case Map.fetch(value, key) do
      {:ok, stored_value} -> stored_value
      :error -> Map.get(value, reference_atom_key(key))
    end
  end

  defp put_reference_value(value, key, normalized) do
    value
    |> Map.delete(reference_atom_key(key))
    |> Map.put(key, normalized)
  end

  defp reference_atom_key("target_type"), do: :target_type
  defp reference_atom_key("target_id"), do: :target_id

  defp extract_block_references(block) do
    case block.type do
      "reference" ->
        extract_reference_block_refs(block)

      "rich_text" ->
        extract_rich_text_refs(block)

      _ ->
        []
    end
  end

  defp extract_reference_block_refs(block) do
    target_type = get_in(block.value, ["target_type"])
    target_id = get_in(block.value, ["target_id"])

    if target_type && target_id do
      [%{type: target_type, id: target_id, context: "value"}]
    else
      []
    end
  end

  defp extract_rich_text_refs(block) do
    content = block.value["content"] || block.value[:content] || ""
    extract_mentions_from_html(content)
  end

  defp extract_mentions_from_html(content) when is_binary(content) do
    case strict_mentions_from_html(content) do
      {:ok, references} -> references
      {:error, _reason} -> []
    end
  end

  defp extract_mentions_from_html(_), do: []

  defp strict_mentions_from_html(content) when is_binary(content) do
    case RichTextMentions.extract_from_html(content) do
      {:ok, mentions} ->
        {:ok, Enum.map(mentions, &Map.put(&1, :context, "content"))}

      {:error, {:invalid_html, reason}} ->
        {:error, {:invalid_project_reference, {:block, :content, :invalid_html}, reason}}

      {:error, {:invalid_mention, details}} ->
        invalid_mention_reference(details)
    end
  end

  defp strict_mentions_from_html(content) do
    {:error, {:invalid_project_reference, {:block, :content, :invalid_html}, content}}
  end

  defp invalid_mention_reference(%{type: [type], id: [id]}) do
    {:error, {:invalid_project_reference, {:block, :content, type}, id}}
  end

  defp invalid_mention_reference(details) do
    {:error, {:invalid_project_reference, {:block, :content, :malformed_mention}, details}}
  end

  defp mention_reference_spec(%{type: "sheet", id: id}), do: {:sheet, {:block, :content, "sheet"}, id}

  defp mention_reference_spec(%{type: "flow", id: id}), do: {:flow, {:block, :content, "flow"}, id}

  defp extract_flow_node_refs(data) do
    refs = []

    # Extract speaker reference (stored as speaker_sheet_id integer)
    refs = maybe_add_sheet_ref(refs, data["speaker_sheet_id"], "speaker")

    # Extract location reference (stored as location_sheet_id integer)
    refs = maybe_add_sheet_ref(refs, data["location_sheet_id"], "location")

    # Mentions are supported anywhere in persisted node JSON (dialogue text,
    # response text, and future nested rich-text fields). Keep this scope in
    # lockstep with Flow reference validation so every accepted mention gets a
    # corresponding entity_references row.
    mention_refs =
      data
      |> RichTextMentions.html_candidates()
      |> Enum.flat_map(&extract_mentions_from_html/1)
      |> Enum.map(&Map.put(&1, :context, "dialogue"))

    mention_refs ++ refs
  end

  defp maybe_add_sheet_ref(refs, nil, _context), do: refs
  defp maybe_add_sheet_ref(refs, "", _context), do: refs

  defp maybe_add_sheet_ref(refs, sheet_id, context) do
    [%{type: "sheet", id: sheet_id, context: context} | refs]
  end

  defp extract_map_pin_refs(pin) do
    refs = []

    # Track flow_id (dedicated flow link)
    refs =
      if pin.flow_id do
        [%{type: "flow", id: pin.flow_id, context: "target"} | refs]
      else
        refs
      end

    # Track sheet_id (avatar/display sheet)
    refs =
      if pin.sheet_id do
        [%{type: "sheet", id: pin.sheet_id, context: "display"} | refs]
      else
        refs
      end

    refs
  end

  defp extract_map_zone_refs(zone) do
    refs = []

    # Track target_type/target_id (navigate link)
    refs =
      if zone.target_type && zone.target_id do
        [%{type: zone.target_type, id: zone.target_id, context: "target"} | refs]
      else
        refs
      end

    # Track sheet references from action_data (action assignments, display variable_ref)
    refs = refs ++ extract_zone_action_data_refs(zone)

    refs
  end

  defp extract_zone_action_data_refs(%{action_type: "action", action_data: action_data} = zone)
       when is_map(action_data) do
    assignments = action_data["assignments"] || []
    project_id = get_project_id_from_scene(zone.scene_id)

    if project_id do
      assignments
      |> Enum.flat_map(&extract_assignment_sheet_refs(&1, project_id))
      |> Enum.uniq_by(fn ref -> {ref.type, ref.id} end)
    else
      []
    end
  end

  defp extract_zone_action_data_refs(%{action_type: "display", action_data: action_data} = zone)
       when is_map(action_data) do
    variable_ref = action_data["variable_ref"]
    resolve_display_sheet_ref(zone.scene_id, variable_ref)
  end

  defp extract_zone_action_data_refs(%{action_type: "collection", action_data: %{"items" => items}})
       when is_list(items) do
    items
    |> Enum.flat_map(fn
      %{"sheet_id" => sheet_id} when is_integer(sheet_id) ->
        [%{type: "sheet", id: sheet_id, context: "collection_item"}]

      _item ->
        []
    end)
    |> Enum.uniq_by(fn reference -> {reference.type, reference.id} end)
  end

  defp extract_zone_action_data_refs(_zone), do: []

  defp resolve_display_sheet_ref(_scene_id, ref) when not is_binary(ref) or ref == "", do: []

  defp resolve_display_sheet_ref(scene_id, variable_ref) do
    with [sheet_shortcut, _variable] <- String.split(variable_ref, ".", parts: 2),
         project_id when not is_nil(project_id) <- get_project_id_from_scene(scene_id) do
      resolve_sheet_ref(project_id, sheet_shortcut, "display")
    else
      _ -> []
    end
  end

  defp extract_assignment_sheet_refs(assignment, project_id) do
    write_refs = resolve_sheet_ref(project_id, assignment["sheet"], "assignment")

    read_refs =
      if assignment["value_type"] == "variable_ref" do
        resolve_sheet_ref(project_id, assignment["value_sheet"], "assignment_source")
      else
        []
      end

    write_refs ++ read_refs
  end

  defp resolve_sheet_ref(_project_id, nil, _context), do: []
  defp resolve_sheet_ref(_project_id, "", _context), do: []

  defp resolve_sheet_ref(project_id, sheet_shortcut, context) do
    sheet_id =
      Repo.one(
        from(s in Sheet,
          where:
            s.project_id == ^project_id and
              fragment("COALESCE(?, CAST(? AS TEXT))", s.shortcut, s.id) ==
                ^sheet_shortcut,
          where: is_nil(s.deleted_at),
          select: s.id,
          limit: 1
        )
      )

    if sheet_id do
      [%{type: "sheet", id: sheet_id, context: context}]
    else
      []
    end
  end

  defp get_project_id_from_scene(nil), do: nil
  defp get_project_id_from_scene(scene_id), do: Storyarn.Scenes.get_scene_project_id(scene_id)
end
