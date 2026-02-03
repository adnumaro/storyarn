defmodule Storyarn.Pages.ReferenceTracker do
  @moduledoc """
  Tracks entity references for building backlinks.

  This module provides functions to:
  - Extract references from rich_text content (mentions)
  - Extract references from reference blocks
  - Update references atomically when content changes
  - Query backlinks for a given target
  """

  import Ecto.Query
  alias Storyarn.Pages.EntityReference
  alias Storyarn.Repo

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
  - source_parent (page/flow that contains the source)

  Optimized to use JOINs instead of N+1 queries.
  """
  @spec get_backlinks_with_sources(String.t(), any(), integer()) :: [map()]
  def get_backlinks_with_sources(target_type, target_id, project_id) do
    alias Storyarn.Pages.{Block, Page}
    alias Storyarn.Flows.{Flow, FlowNode}

    # Single query for block references with JOINs
    block_refs =
      from(r in EntityReference,
        join: b in Block,
        on: r.source_type == "block" and r.source_id == b.id,
        join: p in Page,
        on: b.page_id == p.id,
        where: r.target_type == ^target_type and r.target_id == ^target_id,
        where: p.project_id == ^project_id and is_nil(p.deleted_at) and is_nil(b.deleted_at),
        select: %{
          id: r.id,
          source_type: r.source_type,
          source_id: r.source_id,
          context: r.context,
          inserted_at: r.inserted_at,
          block_type: b.type,
          block_label: fragment("?->>'label'", b.config),
          page_id: p.id,
          page_name: p.name,
          page_shortcut: p.shortcut
        },
        order_by: [desc: r.inserted_at]
      )
      |> Repo.all()

    # Single query for flow node references with JOINs
    flow_node_refs =
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

    # Transform to expected format
    block_backlinks =
      Enum.map(block_refs, fn ref ->
        %{
          id: ref.id,
          source_type: "block",
          source_id: ref.source_id,
          context: ref.context,
          inserted_at: ref.inserted_at,
          source_info: %{
            type: :page,
            page_id: ref.page_id,
            page_name: ref.page_name,
            page_shortcut: ref.page_shortcut,
            block_type: ref.block_type,
            block_label: ref.block_label
          }
        }
      end)

    flow_backlinks =
      Enum.map(flow_node_refs, fn ref ->
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

    # Combine and sort by inserted_at desc
    (block_backlinks ++ flow_backlinks)
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
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
  Called when permanently deleting a page or flow.
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
    alias Storyarn.Pages.Block
    alias Storyarn.Pages.Page
    alias Storyarn.Flows.Flow

    # Clean up references where source block no longer exists
    from(r in EntityReference,
      where: r.source_type == "block",
      where: fragment("NOT EXISTS (SELECT 1 FROM blocks WHERE id = ?)", r.source_id)
    )
    |> Repo.delete_all()

    # Clean up references where target page no longer exists (hard deleted)
    from(r in EntityReference,
      where: r.target_type == "page",
      where: fragment("NOT EXISTS (SELECT 1 FROM pages WHERE id = ?)", r.target_id)
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
    # Extract mentions from HTML: <span class="mention" data-type="page" data-id="123" data-label="name">
    Regex.scan(
      ~r/<span[^>]*class="mention"[^>]*data-type="([^"]+)"[^>]*data-id="([^"]+)"/,
      content
    )
    |> Enum.map(fn [_, type, id] ->
      %{type: type, id: id, context: "content"}
    end)
  end

  defp extract_mentions_from_html(_), do: []

  defp extract_flow_node_refs(data) do
    refs = []

    # Extract speaker reference (speaker can be a map with id, or just a string name)
    refs =
      case data["speaker"] do
        %{"id" => speaker_id} when not is_nil(speaker_id) ->
          [%{type: "page", id: speaker_id, context: "speaker"} | refs]

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
