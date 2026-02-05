defmodule Storyarn.Pages.PageCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Pages.Page
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Shortcuts

  # =============================================================================
  # CRUD Operations
  # =============================================================================

  def create_page(%Project{} = project, attrs) do
    # Normalize keys to strings for changeset
    attrs = stringify_keys(attrs)
    parent_id = attrs["parent_id"]
    position = attrs["position"] || next_position(project.id, parent_id)

    # Auto-generate shortcut from name if not provided
    attrs = maybe_generate_shortcut(attrs, project.id, nil)

    %Page{project_id: project.id}
    |> Page.create_changeset(Map.put(attrs, "position", position))
    |> Repo.insert()
  end

  def update_page(%Page{} = page, attrs) do
    # Auto-generate shortcut if page has no shortcut and name is being updated
    attrs = maybe_generate_shortcut_on_update(page, attrs)

    page
    |> Page.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Soft deletes a page (moves to trash).
  Also soft deletes all descendant pages.
  """
  def delete_page(%Page{} = page) do
    trash_page(page)
  end

  @doc """
  Soft deletes a page and all its descendants (moves to trash).
  """
  def trash_page(%Page{} = page) do
    Repo.transaction(fn ->
      # Get all descendant IDs before deleting
      descendant_ids = get_descendant_ids(page.id)

      # Soft delete all descendants
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      if descendant_ids != [] do
        from(p in Page, where: p.id in ^descendant_ids)
        |> Repo.update_all(set: [deleted_at: now])
      end

      # Soft delete the page itself
      page
      |> Page.delete_changeset()
      |> Repo.update!()
    end)
  end

  @doc """
  Restores a soft-deleted page from trash.
  Also restores all soft-deleted blocks for this page.
  Note: Does not automatically restore descendant pages.
  """
  def restore_page(%Page{} = page) do
    alias Storyarn.Pages.Block

    Ecto.Multi.new()
    |> Ecto.Multi.update(:page, Page.restore_changeset(page))
    |> Ecto.Multi.run(:restore_blocks, fn repo, _changes ->
      # Restore all soft-deleted blocks for this page
      {count, _} =
        from(b in Block,
          where: b.page_id == ^page.id and not is_nil(b.deleted_at)
        )
        |> repo.update_all(set: [deleted_at: nil])

      {:ok, count}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{page: page}} -> {:ok, page}
      {:error, _op, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Permanently deletes a page and all its descendants.
  Use with caution - this cannot be undone.
  """
  def permanently_delete_page(%Page{} = page) do
    alias Storyarn.Pages.{PageVersion, ReferenceTracker}

    # Delete all versions first
    from(v in PageVersion, where: v.page_id == ^page.id)
    |> Repo.delete_all()

    # Delete references where this page is the target
    ReferenceTracker.delete_target_references("page", page.id)

    # Delete the page (blocks cascade via FK)
    Repo.delete(page)
  end

  def move_page(%Page{} = page, parent_id, position \\ nil) do
    with :ok <- validate_parent(page, parent_id) do
      position = position || next_position(page.project_id, parent_id)

      page
      |> Page.move_changeset(%{parent_id: parent_id, position: position})
      |> Repo.update()
    end
  end

  def change_page(%Page{} = page, attrs \\ %{}) do
    Page.update_changeset(page, attrs)
  end

  # =============================================================================
  # Validation
  # =============================================================================

  def validate_parent(%Page{} = page, parent_id) do
    cond do
      is_nil(parent_id) ->
        :ok

      parent_id == page.id ->
        {:error, :cannot_be_own_parent}

      true ->
        case Repo.get(Page, parent_id) do
          nil ->
            {:error, :parent_not_found}

          parent ->
            validate_parent_page(page, parent)
        end
    end
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp validate_parent_page(page, parent) do
    cond do
      parent.project_id != page.project_id ->
        {:error, :parent_different_project}

      descendant?(parent.id, page.id) ->
        {:error, :would_create_cycle}

      true ->
        :ok
    end
  end

  defp get_descendant_ids(page_id) do
    direct_children_ids =
      from(p in Page,
        where: p.parent_id == ^page_id and is_nil(p.deleted_at),
        select: p.id
      )
      |> Repo.all()

    Enum.flat_map(direct_children_ids, fn child_id ->
      [child_id | get_descendant_ids(child_id)]
    end)
  end

  defp descendant?(potential_descendant_id, ancestor_id) do
    descendant_ids = get_descendant_ids(ancestor_id)
    potential_descendant_id in descendant_ids
  end

  defp next_position(project_id, parent_id) do
    query =
      from(p in Page,
        where: p.project_id == ^project_id and is_nil(p.deleted_at),
        select: max(p.position)
      )

    query =
      if is_nil(parent_id) do
        where(query, [p], is_nil(p.parent_id))
      else
        where(query, [p], p.parent_id == ^parent_id)
      end

    (Repo.one(query) || -1) + 1
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp maybe_generate_shortcut(attrs, project_id, exclude_page_id) do
    # Only generate if shortcut is not provided and name is available
    has_shortcut = Map.has_key?(attrs, "shortcut") || Map.has_key?(attrs, :shortcut)
    name = attrs["name"] || attrs[:name]

    if has_shortcut || is_nil(name) || name == "" do
      attrs
    else
      shortcut = Shortcuts.generate_page_shortcut(name, project_id, exclude_page_id)
      Map.put(attrs, "shortcut", shortcut)
    end
  end

  defp maybe_generate_shortcut_on_update(%Page{} = page, attrs) do
    attrs = stringify_keys(attrs)

    # If attrs explicitly set shortcut, use that
    if Map.has_key?(attrs, "shortcut") do
      attrs
    else
      # If name is changing, regenerate shortcut from new name
      new_name = attrs["name"]

      if new_name && new_name != "" && new_name != page.name do
        shortcut = Shortcuts.generate_page_shortcut(new_name, page.project_id, page.id)
        Map.put(attrs, "shortcut", shortcut)
      else
        # If page has no shortcut yet, generate one from current name
        if is_nil(page.shortcut) || page.shortcut == "" do
          name = page.name

          if name && name != "" do
            shortcut = Shortcuts.generate_page_shortcut(name, page.project_id, page.id)
            Map.put(attrs, "shortcut", shortcut)
          else
            attrs
          end
        else
          attrs
        end
      end
    end
  end
end
