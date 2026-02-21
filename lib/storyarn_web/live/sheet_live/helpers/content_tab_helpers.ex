defmodule StoryarnWeb.SheetLive.Helpers.ContentTabHelpers do
  @moduledoc """
  Pure, stateless helper functions for the ContentTab LiveComponent.

  Covers:
  - Block layout grouping (full-width vs column groups)
  - Reference enrichment
  - Column item sanitisation and validation
  - Integer parsing utility
  """

  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Sheets

  # ---------------------------------------------------------------------------
  # Integer parsing
  # ---------------------------------------------------------------------------

  @doc "Coerces a binary or integer block-ID to an integer. Returns nil for invalid input."
  def to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  def to_integer(value) when is_integer(value), do: value
  def to_integer(_), do: nil

  # ---------------------------------------------------------------------------
  # Block layout
  # ---------------------------------------------------------------------------

  @doc """
  Groups a flat, ordered list of blocks into layout items.

  Each item is either `%{type: :full_width, block: block}` or
  `%{type: :column_group, group_id: id, blocks: [...], column_count: n}`.
  """
  def group_blocks_for_layout(blocks) do
    blocks
    |> Enum.chunk_by(fn block -> block.column_group_id end)
    |> Enum.flat_map(&chunk_to_layout_items/1)
  end

  @doc "Returns the Tailwind grid-cols class for the given column count."
  def column_grid_class(2), do: "sm:grid-cols-2"
  def column_grid_class(3), do: "sm:grid-cols-3"
  def column_grid_class(_), do: "sm:grid-cols-1"

  # ---------------------------------------------------------------------------
  # Reference enrichment
  # ---------------------------------------------------------------------------

  @doc """
  Adds a `:reference_target` virtual field to every block in the list.

  For `reference`-type blocks the target entity is fetched; all others get `nil`.
  """
  def enrich_with_references(blocks, project_id) do
    Enum.map(blocks, fn block ->
      if block.type == "reference" do
        target_type = get_in(block.value, ["target_type"])
        target_id = get_in(block.value, ["target_id"])
        reference_target = Sheets.get_reference_target(target_type, target_id, project_id)
        Map.put(block, :reference_target, reference_target)
      else
        Map.put(block, :reference_target, nil)
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Column group sanitisation / validation
  # ---------------------------------------------------------------------------

  @doc """
  Converts a raw JS column-item map to the internal representation, or `nil`
  if the block does not belong to the sheet (security check).
  """
  def sanitize_column_item(item, blocks_by_id) do
    block_id = to_integer(item["id"])
    block = Map.get(blocks_by_id, block_id)

    if block do
      column_group_id =
        if block.type in ["divider", "table"], do: nil, else: item["column_group_id"]

      column_index =
        if column_group_id == nil, do: 0, else: item["column_index"] || 0

      %{
        id: block_id,
        column_group_id: column_group_id,
        column_index: column_index
      }
    end
  end

  @doc "Validates that the given blocks can form a new column group."
  def validate_column_group_blocks(blocks) do
    cond do
      Enum.any?(blocks, &is_nil/1) ->
        {:error, dgettext("sheets", "Block not found.")}

      Enum.any?(blocks, fn b -> b.type in ["divider", "table"] end) ->
        {:error, dgettext("sheets", "This block type cannot be placed in columns.")}

      Enum.any?(blocks, fn b -> b.column_group_id != nil end) ->
        {:error, dgettext("sheets", "Block is already in a column group.")}

      true ->
        :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp chunk_to_layout_items(chunk) do
    first = List.first(chunk)

    if first.column_group_id != nil and length(chunk) >= 2 do
      sorted = Enum.sort_by(chunk, & &1.column_index)
      column_count = min(length(sorted), 3)

      [
        %{
          type: :column_group,
          group_id: first.column_group_id,
          blocks: sorted,
          column_count: column_count
        }
      ]
    else
      Enum.map(chunk, fn block ->
        %{type: :full_width, block: block}
      end)
    end
  end
end
