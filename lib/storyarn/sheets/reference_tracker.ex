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
  - **Orphaned references**: Stale references are cleaned up during bulk deletions
  - **Cross-project**: References are always scoped to a single project

  ## Performance

  - Backlinks query is optimized with JOINs (no N+1)
  - Indexes exist on (source_type, source_id) and (target_type, target_id)
  """

  import Ecto.Query
  alias Storyarn.Repo

  alias Storyarn.Sheets.{EntityReference, Sheet}

  @doc """
  Updates references from a block.

  Deletes all existing references from this block and creates new ones
  based on the current block state.
  """
  @spec update_block_references(map()) :: :ok
  def update_block_references(block) do
    block_id = block.id

    # Delete existing references from this block
    from(r in EntityReference,
      where: r.source_type == "block" and r.source_id == ^block_id
    )
    |> Repo.delete_all()

    # Extract and batch-insert new references
    references = extract_block_references(block)
    batch_insert_references("block", block_id, references)
  end

  @doc """
  Deletes all references from a block.
  Called when a block is deleted.
  """
  @spec delete_block_references(any()) :: {integer(), nil}
  def delete_block_references(block_id) do
    from(r in EntityReference,
      where: r.source_type == "block" and r.source_id == ^block_id
    )
    |> Repo.delete_all()
  end

  @doc """
  Updates references for a flow node based on its data.
  Extracts mentions from rich text fields and speaker references.
  """
  @spec update_flow_node_references(map()) :: :ok
  def update_flow_node_references(%{id: node_id, data: data}) when is_map(data) do
    # Delete existing references from this node
    delete_flow_node_references(node_id)

    references = extract_flow_node_refs(data)
    batch_insert_references("flow_node", node_id, references)
  end

  def update_flow_node_references(_node), do: :ok

  @doc """
  Deletes all references from a flow node.
  Called when a node is deleted.
  """
  @spec delete_flow_node_references(any()) :: {integer(), nil}
  def delete_flow_node_references(node_id) do
    from(r in EntityReference,
      where: r.source_type == "flow_node" and r.source_id == ^node_id
    )
    |> Repo.delete_all()
  end

  @doc """
  Updates references from a screenplay element.

  Deletes all existing references from this element and creates new ones
  based on the current element state (character sheet_id + inline mentions).
  """
  @spec update_screenplay_element_references(map()) :: :ok
  def update_screenplay_element_references(%{
        id: element_id,
        type: type,
        data: data,
        content: content
      }) do
    delete_screenplay_element_references(element_id)

    references =
      extract_screenplay_element_refs(type, data, content)
      |> Enum.uniq_by(fn ref -> {ref.type, ref.id, ref.context} end)

    batch_insert_references("screenplay_element", element_id, references)
  end

  def update_screenplay_element_references(_element), do: :ok

  @doc """
  Deletes all references from a screenplay element.
  Called when an element is deleted.
  """
  @spec delete_screenplay_element_references(any()) :: {integer(), nil}
  def delete_screenplay_element_references(element_id) do
    from(r in EntityReference,
      where: r.source_type == "screenplay_element" and r.source_id == ^element_id
    )
    |> Repo.delete_all()
  end

  @doc """
  Gets all references pointing to a target (backlinks).

  Returns references grouped by source type with additional context.
  """
  @spec get_backlinks(String.t(), any()) :: [map()]
  def get_backlinks(target_type, target_id) do
    from(r in EntityReference,
      where: r.target_type == ^target_type and r.target_id == ^target_id,
      order_by: [desc: r.inserted_at]
    )
    |> Repo.all()
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
    screenplay_backlinks = query_screenplay_element_backlinks(target_type, target_id, project_id)
    map_pin_backlinks = query_scene_pin_backlinks(target_type, target_id, project_id)
    map_zone_backlinks = query_scene_zone_backlinks(target_type, target_id, project_id)

    (block_backlinks ++
       flow_backlinks ++ screenplay_backlinks ++ map_pin_backlinks ++ map_zone_backlinks)
    |> Enum.sort_by(& &1.inserted_at, {:desc, NaiveDateTime})
  end

  defp query_block_backlinks(target_type, target_id, project_id) do
    alias Storyarn.Sheets.{Block, Sheet}

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

  defp query_screenplay_element_backlinks(target_type, target_id, project_id) do
    Storyarn.Screenplays.query_screenplay_element_backlinks(target_type, target_id, project_id)
  end

  @doc """
  Counts backlinks for a target.
  """
  @spec count_backlinks(String.t(), any()) :: integer()
  def count_backlinks(target_type, target_id) do
    from(r in EntityReference,
      where: r.target_type == ^target_type and r.target_id == ^target_id,
      select: count(r.id)
    )
    |> Repo.one()
  end

  # ---------------------------------------------------------------------------
  # Map element references (pins & zones)
  # ---------------------------------------------------------------------------

  @doc """
  Updates references from a map pin.
  Tracks target_type/target_id and sheet_id references.
  """
  @spec update_scene_pin_references(map()) :: :ok
  def update_scene_pin_references(%{id: pin_id} = pin) do
    delete_map_pin_references(pin_id)

    refs = extract_map_pin_refs(pin)
    batch_insert_references("scene_pin", pin_id, refs)
  end

  def update_scene_pin_references(_pin), do: :ok

  @doc """
  Deletes all references from a map pin.
  """
  @spec delete_map_pin_references(any()) :: {integer(), nil}
  def delete_map_pin_references(pin_id) do
    from(r in EntityReference,
      where: r.source_type == "scene_pin" and r.source_id == ^pin_id
    )
    |> Repo.delete_all()
  end

  @doc """
  Updates references from a map zone.
  Tracks target_type/target_id references.
  """
  @spec update_scene_zone_references(map()) :: :ok
  def update_scene_zone_references(%{id: zone_id} = zone) do
    delete_map_zone_references(zone_id)

    refs = extract_map_zone_refs(zone)
    batch_insert_references("scene_zone", zone_id, refs)
  end

  def update_scene_zone_references(_zone), do: :ok

  @doc """
  Deletes all references from a map zone.
  """
  @spec delete_map_zone_references(any()) :: {integer(), nil}
  def delete_map_zone_references(zone_id) do
    from(r in EntityReference,
      where: r.source_type == "scene_zone" and r.source_id == ^zone_id
    )
    |> Repo.delete_all()
  end

  @doc """
  Deletes all references pointing to a specific target.
  Called when permanently deleting a sheet or flow.
  """
  @spec delete_target_references(String.t(), any()) :: {integer(), nil}
  def delete_target_references(target_type, target_id) do
    from(r in EntityReference,
      where: r.target_type == ^target_type and r.target_id == ^target_id
    )
    |> Repo.delete_all()
  end

  defp query_scene_pin_backlinks(target_type, target_id, project_id) do
    Storyarn.Scenes.query_scene_pin_backlinks(target_type, target_id, project_id)
  end

  defp query_scene_zone_backlinks(target_type, target_id, project_id) do
    Storyarn.Scenes.query_scene_zone_backlinks(target_type, target_id, project_id)
  end

  # Private functions

  defp batch_insert_references(source_type, source_id, references) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    entries =
      references
      |> Enum.map(fn ref -> parse_id(ref.id) |> then(&{&1, ref}) end)
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

    if entries != [], do: Repo.insert_all(EntityReference, entries, on_conflict: :nothing)

    :ok
  end

  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_id(_), do: nil

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
    content = get_in(block.value, ["content"]) || ""
    extract_mentions_from_html(content)
  end

  defp extract_mentions_from_html(content) when is_binary(content) do
    # Use Floki for robust HTML parsing instead of regex
    case Floki.parse_fragment(content) do
      {:ok, document} ->
        document
        |> Floki.find("span.mention")
        |> Enum.map(&mention_element_to_ref/1)
        |> Enum.reject(&is_nil/1)

      {:error, _} ->
        []
    end
  end

  defp extract_mentions_from_html(_), do: []

  defp mention_element_to_ref(element) do
    type = Floki.attribute(element, "data-type") |> List.first()
    id = Floki.attribute(element, "data-id") |> List.first()

    if type && id do
      %{type: type, id: id, context: "content"}
    end
  end

  defp extract_screenplay_element_refs(type, data, content) do
    refs = []

    # Character elements: track sheet_id reference
    refs =
      if type == "character" && is_map(data) do
        case data["sheet_id"] do
          nil -> refs
          sheet_id -> [%{type: "sheet", id: sheet_id, context: "character"} | refs]
        end
      else
        refs
      end

    # Any element with HTML content: extract inline mentions
    refs =
      if is_binary(content) && content != "" do
        mentions = extract_mentions_from_html(content)
        mentions ++ refs
      else
        refs
      end

    refs
  end

  defp extract_flow_node_refs(data) do
    refs = []

    # Extract speaker reference (stored as speaker_sheet_id integer)
    refs = maybe_add_sheet_ref(refs, data["speaker_sheet_id"], "speaker")

    # Extract location reference (stored as location_sheet_id integer)
    refs = maybe_add_sheet_ref(refs, data["location_sheet_id"], "location")

    # Extract mentions from dialogue text
    refs =
      if text = data["text"] do
        mentions = extract_mentions_from_html(text)
        Enum.map(mentions, fn m -> Map.put(m, :context, "dialogue") end) ++ refs
      else
        refs
      end

    refs
  end

  defp maybe_add_sheet_ref(refs, nil, _context), do: refs
  defp maybe_add_sheet_ref(refs, "", _context), do: refs

  defp maybe_add_sheet_ref(refs, sheet_id, context) do
    [%{type: "sheet", id: sheet_id, context: context} | refs]
  end

  defp extract_map_pin_refs(pin) do
    refs = []

    # Track target_type/target_id (navigate link)
    refs =
      if pin.target_type && pin.target_id do
        [%{type: pin.target_type, id: pin.target_id, context: "target"} | refs]
      else
        refs
      end

    # Track sheet_id (avatar/display sheet — separate from target)
    refs =
      if pin.sheet_id && pin.sheet_id != pin.target_id do
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

    # Track sheet references from action_data (instruction assignments, display variable_ref)
    refs = refs ++ extract_zone_action_data_refs(zone)

    refs
  end

  defp extract_zone_action_data_refs(
         %{action_type: "instruction", action_data: action_data} = zone
       )
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
      from(s in Sheet,
        where: s.project_id == ^project_id and s.shortcut == ^sheet_shortcut,
        where: is_nil(s.deleted_at),
        select: s.id,
        limit: 1
      )
      |> Repo.one()

    if sheet_id do
      [%{type: "sheet", id: sheet_id, context: context}]
    else
      []
    end
  end

  defp get_project_id_from_scene(nil), do: nil
  defp get_project_id_from_scene(scene_id), do: Storyarn.Scenes.get_scene_project_id(scene_id)
end
