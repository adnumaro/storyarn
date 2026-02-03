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
  """
  @spec get_backlinks_with_sources(String.t(), any(), integer()) :: [map()]
  def get_backlinks_with_sources(target_type, target_id, project_id) do
    references =
      from(r in EntityReference,
        where: r.target_type == ^target_type and r.target_id == ^target_id,
        order_by: [desc: r.inserted_at]
      )
      |> Repo.all()

    # Resolve source information for each reference
    Enum.map(references, fn ref ->
      source_info = resolve_source_info(ref, project_id)

      %{
        id: ref.id,
        source_type: ref.source_type,
        source_id: ref.source_id,
        context: ref.context,
        inserted_at: ref.inserted_at,
        source_info: source_info
      }
    end)
    |> Enum.filter(fn ref -> ref.source_info != nil end)
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

    # Extract mentions from HTML: <span class="mention" data-type="page" data-id="123" data-label="name">
    Regex.scan(
      ~r/<span[^>]*class="mention"[^>]*data-type="([^"]+)"[^>]*data-id="([^"]+)"/,
      content
    )
    |> Enum.map(fn [_, type, id] ->
      %{type: type, id: id, context: "content"}
    end)
  end

  defp resolve_source_info(%{source_type: "block", source_id: source_id}, project_id) do
    alias Storyarn.Pages.Block
    alias Storyarn.Pages.Page

    block =
      from(b in Block,
        join: p in Page,
        on: b.page_id == p.id,
        where: b.id == ^source_id and p.project_id == ^project_id and is_nil(p.deleted_at),
        select: {b, p}
      )
      |> Repo.one()

    case block do
      {block, page} ->
        label = get_in(block.config, ["label"]) || block.type

        %{
          type: "page",
          page_id: page.id,
          page_name: page.name,
          page_shortcut: page.shortcut,
          block_id: block.id,
          block_label: label,
          block_type: block.type
        }

      nil ->
        nil
    end
  end

  defp resolve_source_info(%{source_type: "flow_node", source_id: source_id}, project_id) do
    alias Storyarn.Flows.{Flow, FlowNode}

    node =
      from(n in FlowNode,
        join: f in Flow,
        on: n.flow_id == f.id,
        where: n.id == ^source_id and f.project_id == ^project_id,
        select: {n, f}
      )
      |> Repo.one()

    case node do
      {node, flow} ->
        %{
          type: "flow",
          flow_id: flow.id,
          flow_name: flow.name,
          flow_shortcut: flow.shortcut,
          node_id: node.id,
          node_type: node.type
        }

      nil ->
        nil
    end
  end
end
