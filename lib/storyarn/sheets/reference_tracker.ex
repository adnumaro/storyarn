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
  - **Orphaned references**: Use `cleanup_orphaned_references/0` to remove stale data
  - **Cross-project**: References are always scoped to a single project

  ## Performance

  - Backlinks query is optimized with JOINs (no N+1)
  - Indexes exist on (source_type, source_id) and (target_type, target_id)
  """

  import Ecto.Query
  alias Storyarn.Repo
  alias Storyarn.Sheets.EntityReference

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

    # Extract and create new references
    references = extract_block_references(block)

    for ref <- references do
      target_id = parse_id(ref.id)

      if target_id do
        %EntityReference{}
        |> EntityReference.changeset(%{
          source_type: "block",
          source_id: block_id,
          target_type: ref.type,
          target_id: target_id,
          context: ref.context
        })
        |> Repo.insert(on_conflict: :nothing)
      end
    end

    :ok
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

    for ref <- references do
      target_id = parse_id(ref.id)

      if target_id do
        %EntityReference{}
        |> EntityReference.changeset(%{
          source_type: "flow_node",
          source_id: node_id,
          target_type: ref.type,
          target_id: target_id,
          context: ref.context
        })
        |> Repo.insert(on_conflict: :nothing)
      end
    end

    :ok
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

    for ref <- references do
      target_id = parse_id(ref.id)

      if target_id do
        %EntityReference{}
        |> EntityReference.changeset(%{
          source_type: "screenplay_element",
          source_id: element_id,
          target_type: ref.type,
          target_id: target_id,
          context: ref.context
        })
        |> Repo.insert(on_conflict: :nothing)
      end
    end

    :ok
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

    (block_backlinks ++ flow_backlinks ++ screenplay_backlinks)
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
    alias Storyarn.Flows.{Flow, FlowNode}

    from(r in EntityReference,
      join: n in FlowNode,
      on: r.source_type == "flow_node" and r.source_id == n.id,
      join: f in Flow,
      on: n.flow_id == f.id,
      where: r.target_type == ^target_type and r.target_id == ^target_id,
      where: f.project_id == ^project_id,
      select: %{
        id: r.id,
        source_type: r.source_type,
        source_id: r.source_id,
        context: r.context,
        inserted_at: r.inserted_at,
        node_type: n.type,
        flow_id: f.id,
        flow_name: f.name,
        flow_shortcut: f.shortcut
      },
      order_by: [desc: r.inserted_at]
    )
    |> Repo.all()
    |> Enum.map(fn ref ->
      %{
        id: ref.id,
        source_type: "flow_node",
        source_id: ref.source_id,
        context: ref.context,
        inserted_at: ref.inserted_at,
        source_info: %{
          type: :flow,
          flow_id: ref.flow_id,
          flow_name: ref.flow_name,
          flow_shortcut: ref.flow_shortcut,
          node_type: ref.node_type
        }
      }
    end)
  end

  defp query_screenplay_element_backlinks(target_type, target_id, project_id) do
    from(r in EntityReference,
      join: e in Storyarn.Screenplays.ScreenplayElement,
      on: r.source_type == "screenplay_element" and r.source_id == e.id,
      join: s in Storyarn.Screenplays.Screenplay,
      on: e.screenplay_id == s.id,
      where: r.target_type == ^target_type and r.target_id == ^target_id,
      where: s.project_id == ^project_id and is_nil(s.deleted_at),
      select: %{
        id: r.id,
        source_type: r.source_type,
        source_id: r.source_id,
        context: r.context,
        inserted_at: r.inserted_at,
        element_type: e.type,
        screenplay_id: s.id,
        screenplay_name: s.name
      },
      order_by: [desc: r.inserted_at]
    )
    |> Repo.all()
    |> Enum.map(fn ref ->
      %{
        id: ref.id,
        source_type: "screenplay_element",
        source_id: ref.source_id,
        context: ref.context,
        inserted_at: ref.inserted_at,
        source_info: %{
          type: :screenplay,
          screenplay_id: ref.screenplay_id,
          screenplay_name: ref.screenplay_name,
          element_type: ref.element_type
        }
      }
    end)
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

  @doc """
  Cleans up orphaned references where source or target no longer exists.
  Should be called periodically or after bulk deletions.
  """
  @spec cleanup_orphaned_references() :: :ok
  def cleanup_orphaned_references do
    # Clean up references where source block no longer exists
    from(r in EntityReference,
      where: r.source_type == "block",
      where: fragment("NOT EXISTS (SELECT 1 FROM blocks WHERE id = ?)", r.source_id)
    )
    |> Repo.delete_all()

    # Clean up references where target sheet no longer exists (hard deleted)
    from(r in EntityReference,
      where: r.target_type == "sheet",
      where: fragment("NOT EXISTS (SELECT 1 FROM sheets WHERE id = ?)", r.target_id)
    )
    |> Repo.delete_all()

    # Clean up references where source screenplay element no longer exists
    from(r in EntityReference,
      where: r.source_type == "screenplay_element",
      where: fragment("NOT EXISTS (SELECT 1 FROM screenplay_elements WHERE id = ?)", r.source_id)
    )
    |> Repo.delete_all()

    # Clean up references where target flow no longer exists
    from(r in EntityReference,
      where: r.target_type == "flow",
      where: fragment("NOT EXISTS (SELECT 1 FROM flows WHERE id = ?)", r.target_id)
    )
    |> Repo.delete_all()

    :ok
  end

  # Private functions

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

    # Extract speaker reference (speaker can be a map with id, or just a string name)
    refs =
      case data["speaker"] do
        %{"id" => speaker_id} when not is_nil(speaker_id) ->
          [%{type: "sheet", id: speaker_id, context: "speaker"} | refs]

        _ ->
          refs
      end

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
end
