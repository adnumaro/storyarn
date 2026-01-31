defmodule Storyarn.Pages.PageOperations do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Pages.Page
  alias Storyarn.Repo

  @doc """
  Reorders pages within a parent container.

  Takes a project_id, parent_id (nil for root level), and a list of page IDs
  in the desired order. Updates all positions in a single transaction.

  Returns `{:ok, pages}` with the reordered pages or `{:error, reason}`.
  """
  def reorder_pages(project_id, parent_id, page_ids) when is_list(page_ids) do
    Repo.transaction(fn ->
      page_ids
      |> Enum.reject(&is_nil/1)
      |> Enum.with_index()
      |> Enum.each(&update_page_position(&1, project_id, parent_id))

      list_pages_by_parent(project_id, parent_id)
    end)
  end

  @doc """
  Moves a page to a new parent at a specific position, reordering siblings as needed.

  This function handles both same-parent reordering and cross-parent moves.
  It updates the page's parent_id, then rebuilds positions for all affected containers.

  Returns `{:ok, page}` with the moved page or `{:error, reason}`.
  """
  def move_page_to_position(%Page{} = page, new_parent_id, new_position) do
    Repo.transaction(fn ->
      old_parent_id = page.parent_id
      project_id = page.project_id

      # Update the page's parent and position
      {:ok, updated_page} =
        page
        |> Page.move_changeset(%{parent_id: new_parent_id, position: new_position})
        |> Repo.update()

      # Get all siblings in the destination container (including the moved page)
      siblings = list_pages_by_parent(project_id, new_parent_id)

      # Build the new order: insert the moved page at the desired position
      siblings_without_moved = Enum.reject(siblings, &(&1.id == page.id))

      new_order =
        siblings_without_moved
        |> List.insert_at(new_position, updated_page)
        |> Enum.map(& &1.id)

      # Update positions in destination container
      new_order
      |> Enum.with_index()
      |> Enum.each(fn {page_id, index} ->
        update_position_only(page_id, index)
      end)

      # If parent changed, also reorder the source container
      if old_parent_id != new_parent_id do
        reorder_source_container(project_id, old_parent_id)
      end

      # Return the page with updated position
      Repo.get!(Page, page.id)
    end)
  end

  defp update_page_position({page_id, index}, project_id, parent_id) do
    query =
      from(p in Page,
        where: p.id == ^page_id and p.project_id == ^project_id
      )

    query = add_parent_filter(query, parent_id)
    Repo.update_all(query, set: [position: index])
  end

  defp update_position_only(page_id, position) do
    from(p in Page, where: p.id == ^page_id)
    |> Repo.update_all(set: [position: position])
  end

  defp reorder_source_container(project_id, parent_id) do
    list_pages_by_parent(project_id, parent_id)
    |> Enum.with_index()
    |> Enum.each(fn {page, index} ->
      update_position_only(page.id, index)
    end)
  end

  defp add_parent_filter(query, nil), do: where(query, [p], is_nil(p.parent_id))
  defp add_parent_filter(query, parent_id), do: where(query, [p], p.parent_id == ^parent_id)

  defp list_pages_by_parent(project_id, parent_id) do
    from(p in Page,
      where: p.project_id == ^project_id,
      order_by: [asc: p.position, asc: p.name]
    )
    |> add_parent_filter(parent_id)
    |> Repo.all()
  end
end
