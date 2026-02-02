defmodule Storyarn.Pages.BlockCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Pages.{Block, Page}
  alias Storyarn.Repo

  # =============================================================================
  # Query Operations
  # =============================================================================

  def list_blocks(page_id) do
    from(b in Block,
      where: b.page_id == ^page_id and is_nil(b.deleted_at),
      order_by: [asc: b.position]
    )
    |> Repo.all()
  end

  def get_block(block_id) do
    Block
    |> where(id: ^block_id)
    |> where([b], is_nil(b.deleted_at))
    |> Repo.one()
  end

  def get_block!(block_id) do
    Block
    |> where(id: ^block_id)
    |> where([b], is_nil(b.deleted_at))
    |> Repo.one!()
  end

  # =============================================================================
  # CRUD Operations
  # =============================================================================

  def create_block(%Page{} = page, attrs) do
    position = attrs[:position] || next_block_position(page.id)

    config = attrs[:config] || Block.default_config(attrs[:type] || attrs["type"])
    value = attrs[:value] || Block.default_value(attrs[:type] || attrs["type"])

    %Block{page_id: page.id}
    |> Block.create_changeset(
      attrs
      |> Map.put(:position, position)
      |> Map.put_new(:config, config)
      |> Map.put_new(:value, value)
    )
    |> Repo.insert()
  end

  def update_block(%Block{} = block, attrs) do
    block
    |> Block.update_changeset(attrs)
    |> Repo.update()
  end

  def update_block_value(%Block{} = block, value) do
    block
    |> Block.value_changeset(%{value: value})
    |> Repo.update()
  end

  def update_block_config(%Block{} = block, config) do
    block
    |> Block.config_changeset(%{config: config})
    |> Repo.update()
  end

  def delete_block(%Block{} = block) do
    Repo.delete(block)
  end

  def change_block(%Block{} = block, attrs \\ %{}) do
    Block.update_changeset(block, attrs)
  end

  # =============================================================================
  # Reordering
  # =============================================================================

  def reorder_blocks(page_id, block_ids) when is_list(block_ids) do
    Repo.transaction(fn ->
      block_ids
      |> Enum.reject(&is_nil/1)
      |> Enum.with_index()
      |> Enum.each(fn {block_id, index} ->
        from(b in Block,
          where: b.id == ^block_id and b.page_id == ^page_id and is_nil(b.deleted_at)
        )
        |> Repo.update_all(set: [position: index])
      end)

      list_blocks(page_id)
    end)
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp next_block_position(page_id) do
    query =
      from(b in Block,
        where: b.page_id == ^page_id and is_nil(b.deleted_at),
        select: max(b.position)
      )

    (Repo.one(query) || -1) + 1
  end
end
