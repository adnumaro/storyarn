defmodule Storyarn.Screenplays.ScreenplayCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Screenplays.Screenplay
  alias Storyarn.Shared.{MapUtils, ShortcutHelpers, SoftDelete}
  alias Storyarn.Shared.TreeOperations, as: SharedTree
  alias Storyarn.Shortcuts

  @doc """
  Lists all non-deleted, non-draft screenplays for a project.
  """
  def list_screenplays(project_id) do
    from(s in Screenplay,
      where:
        s.project_id == ^project_id and
          is_nil(s.deleted_at) and
          is_nil(s.draft_of_id),
      order_by: [asc: s.position, asc: s.name]
    )
    |> Repo.all()
  end

  @doc """
  Lists screenplays as a tree structure.
  Returns root-level screenplays with children preloaded.
  Excludes drafts and soft-deleted screenplays.
  """
  def list_screenplays_tree(project_id) do
    all =
      from(s in Screenplay,
        where:
          s.project_id == ^project_id and
            is_nil(s.deleted_at) and
            is_nil(s.draft_of_id),
        order_by: [asc: s.position, asc: s.name]
      )
      |> Repo.all()

    build_tree(all, nil)
  end

  defp build_tree(all_items, root_parent_id) do
    grouped = Enum.group_by(all_items, & &1.parent_id)
    build_subtree(grouped, root_parent_id)
  end

  defp build_subtree(grouped, parent_id) do
    (Map.get(grouped, parent_id) || [])
    |> Enum.map(fn item ->
      %{item | children: build_subtree(grouped, item.id)}
    end)
  end

  @doc """
  Gets a screenplay by project_id and screenplay_id.
  Returns nil if not found, deleted, or is a draft.
  Preloads elements ordered by position.
  """
  def get_screenplay(project_id, screenplay_id) do
    from(s in Screenplay,
      where:
        s.project_id == ^project_id and
          s.id == ^screenplay_id and
          is_nil(s.deleted_at) and
          is_nil(s.draft_of_id),
      preload: [
        elements: ^from(e in Storyarn.Screenplays.ScreenplayElement, order_by: e.position)
      ]
    )
    |> Repo.one()
  end

  @doc """
  Gets a screenplay by project_id and screenplay_id.
  Raises if not found, deleted, or is a draft.
  Preloads elements ordered by position.
  """
  def get_screenplay!(project_id, screenplay_id) do
    from(s in Screenplay,
      where:
        s.project_id == ^project_id and
          s.id == ^screenplay_id and
          is_nil(s.deleted_at) and
          is_nil(s.draft_of_id),
      preload: [
        elements: ^from(e in Storyarn.Screenplays.ScreenplayElement, order_by: e.position)
      ]
    )
    |> Repo.one!()
  end

  @doc """
  Creates a screenplay for a project.
  Auto-generates shortcut from name if not provided.
  Auto-assigns position to end of siblings.
  """
  def create_screenplay(%Project{} = project, attrs) do
    attrs = stringify_keys(attrs)

    attrs = maybe_generate_shortcut(attrs, project.id, nil)

    parent_id = attrs["parent_id"]
    attrs = maybe_assign_position(attrs, project.id, parent_id)

    %Screenplay{project_id: project.id}
    |> Screenplay.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a screenplay.
  Auto-generates shortcut if name changes and no explicit shortcut provided.
  """
  def update_screenplay(%Screenplay{} = screenplay, attrs) do
    attrs = maybe_generate_shortcut_on_update(screenplay, attrs)

    screenplay
    |> Screenplay.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Soft-deletes a screenplay by setting deleted_at.
  Also soft-deletes all children recursively.
  """
  def delete_screenplay(%Screenplay{} = screenplay) do
    Repo.transaction(fn ->
      case screenplay |> Screenplay.delete_changeset() |> Repo.update() do
        {:ok, deleted} ->
          SoftDelete.soft_delete_children(Screenplay, screenplay.project_id, screenplay.id)
          deleted

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Restores a soft-deleted screenplay.
  """
  def restore_screenplay(%Screenplay{} = screenplay) do
    screenplay
    |> Screenplay.restore_changeset()
    |> Repo.update()
  end

  @doc """
  Returns a changeset for tracking screenplay changes.
  Used by Form components for validation.
  """
  def change_screenplay(%Screenplay{} = screenplay, attrs \\ %{}) do
    Screenplay.update_changeset(screenplay, attrs)
  end

  @doc """
  Checks if a screenplay exists within a project (non-deleted, non-draft).
  """
  def screenplay_exists?(project_id, screenplay_id) do
    from(s in Screenplay,
      where:
        s.id == ^screenplay_id and s.project_id == ^project_id and
          is_nil(s.deleted_at) and is_nil(s.draft_of_id)
    )
    |> Repo.exists?()
  end

  @doc """
  Lists all soft-deleted screenplays for a project (trash).
  """
  def list_deleted_screenplays(project_id), do: SoftDelete.list_deleted(Screenplay, project_id)

  # Private functions

  defp maybe_generate_shortcut(attrs, project_id, exclude_id) do
    attrs
    |> stringify_keys()
    |> ShortcutHelpers.maybe_generate_shortcut(
      project_id,
      exclude_id,
      &Shortcuts.generate_screenplay_shortcut/3
    )
  end

  defp maybe_generate_shortcut_on_update(%Screenplay{} = screenplay, attrs) do
    ShortcutHelpers.maybe_generate_shortcut_on_update(
      screenplay,
      attrs,
      &Shortcuts.generate_screenplay_shortcut/3
    )
  end

  defp stringify_keys(map), do: MapUtils.stringify_keys(map)

  defp maybe_assign_position(attrs, project_id, parent_id) do
    ShortcutHelpers.maybe_assign_position(
      attrs,
      project_id,
      parent_id,
      &next_position/2
    )
  end

  defp next_position(project_id, parent_id) do
    from(s in Screenplay,
      where: s.project_id == ^project_id and is_nil(s.deleted_at) and is_nil(s.draft_of_id),
      select: max(s.position)
    )
    |> SharedTree.add_parent_filter(parent_id)
    |> Repo.one()
    |> case do
      nil -> 0
      max -> max + 1
    end
  end
end
