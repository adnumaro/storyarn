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
    |> ensure_unique_variable_name(page.id, nil)
    |> Repo.insert()
  end

  def update_block(%Block{} = block, attrs) do
    block
    |> Block.update_changeset(attrs)
    |> ensure_unique_variable_name(block.page_id, block.id)
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
    |> ensure_unique_variable_name(block.page_id, block.id)
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

  # Ensures the variable_name is unique within the page.
  # If a collision exists, adds suffix _2, _3, etc.
  defp ensure_unique_variable_name(changeset, page_id, exclude_block_id) do
    import Ecto.Changeset, only: [get_field: 2, put_change: 3]

    variable_name = get_field(changeset, :variable_name)

    if is_nil(variable_name) do
      changeset
    else
      unique_name = find_unique_variable_name(variable_name, page_id, exclude_block_id)

      if unique_name != variable_name do
        put_change(changeset, :variable_name, unique_name)
      else
        changeset
      end
    end
  end

  defp find_unique_variable_name(base_name, page_id, exclude_block_id) do
    existing_names = list_variable_names(page_id, exclude_block_id)

    if base_name in existing_names do
      find_unique_with_suffix(base_name, existing_names, 2)
    else
      base_name
    end
  end

  defp find_unique_with_suffix(base_name, existing_names, suffix) do
    candidate = "#{base_name}_#{suffix}"

    if candidate in existing_names do
      find_unique_with_suffix(base_name, existing_names, suffix + 1)
    else
      candidate
    end
  end

  defp list_variable_names(page_id, exclude_block_id) do
    query =
      from(b in Block,
        where:
          b.page_id == ^page_id and
            is_nil(b.deleted_at) and
            not is_nil(b.variable_name),
        select: b.variable_name
      )

    query =
      if exclude_block_id do
        where(query, [b], b.id != ^exclude_block_id)
      else
        query
      end

    Repo.all(query)
  end
end
