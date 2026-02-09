defmodule Storyarn.Screenplays.ScreenplayCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Screenplays.Screenplay
  alias Storyarn.Shared.MapUtils
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

  defp build_tree(all, parent_id) do
    all
    |> Enum.filter(&(&1.parent_id == parent_id))
    |> Enum.map(fn screenplay ->
      children = build_tree(all, screenplay.id)
      %{screenplay | children: children}
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
          soft_delete_children(screenplay.project_id, screenplay.id)
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
  Lists all soft-deleted screenplays for a project (trash).
  """
  def list_deleted_screenplays(project_id) do
    from(s in Screenplay,
      where: s.project_id == ^project_id and not is_nil(s.deleted_at),
      order_by: [desc: s.deleted_at]
    )
    |> Repo.all()
  end

  # Private functions

  defp soft_delete_children(project_id, parent_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    children =
      from(s in Screenplay,
        where:
          s.project_id == ^project_id and
            s.parent_id == ^parent_id and
            is_nil(s.deleted_at)
      )
      |> Repo.all()

    Enum.each(children, fn child ->
      from(s in Screenplay, where: s.id == ^child.id)
      |> Repo.update_all(set: [deleted_at: now])

      soft_delete_children(project_id, child.id)
    end)
  end

  defp maybe_generate_shortcut(attrs, project_id, exclude_id) do
    attrs = stringify_keys(attrs)
    has_shortcut = Map.has_key?(attrs, "shortcut")
    name = attrs["name"]

    if has_shortcut || is_nil(name) || name == "" do
      attrs
    else
      shortcut = Shortcuts.generate_screenplay_shortcut(name, project_id, exclude_id)
      Map.put(attrs, "shortcut", shortcut)
    end
  end

  defp maybe_generate_shortcut_on_update(%Screenplay{} = screenplay, attrs) do
    attrs = stringify_keys(attrs)

    cond do
      Map.has_key?(attrs, "shortcut") ->
        attrs

      name_changed?(attrs, screenplay) ->
        shortcut =
          Shortcuts.generate_screenplay_shortcut(
            attrs["name"],
            screenplay.project_id,
            screenplay.id
          )

        Map.put(attrs, "shortcut", shortcut)

      missing_shortcut?(screenplay) ->
        generate_shortcut_from_existing_name(screenplay, attrs)

      true ->
        attrs
    end
  end

  defp name_changed?(attrs, screenplay) do
    new_name = attrs["name"]
    new_name && new_name != "" && new_name != screenplay.name
  end

  defp missing_shortcut?(screenplay) do
    is_nil(screenplay.shortcut) || screenplay.shortcut == ""
  end

  defp generate_shortcut_from_existing_name(screenplay, attrs) do
    name = screenplay.name

    if name && name != "" do
      shortcut =
        Shortcuts.generate_screenplay_shortcut(name, screenplay.project_id, screenplay.id)

      Map.put(attrs, "shortcut", shortcut)
    else
      attrs
    end
  end

  defp stringify_keys(map), do: MapUtils.stringify_keys(map)

  defp maybe_assign_position(attrs, project_id, parent_id) do
    if Map.has_key?(attrs, "position") do
      attrs
    else
      position = next_position(project_id, parent_id)
      Map.put(attrs, "position", position)
    end
  end

  defp next_position(project_id, parent_id) do
    from(s in Screenplay,
      where: s.project_id == ^project_id and is_nil(s.deleted_at) and is_nil(s.draft_of_id),
      select: max(s.position)
    )
    |> add_parent_filter(parent_id)
    |> Repo.one()
    |> case do
      nil -> 0
      max -> max + 1
    end
  end

  defp add_parent_filter(query, nil), do: where(query, [s], is_nil(s.parent_id))
  defp add_parent_filter(query, parent_id), do: where(query, [s], s.parent_id == ^parent_id)
end
