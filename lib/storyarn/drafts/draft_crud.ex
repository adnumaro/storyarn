defmodule Storyarn.Drafts.DraftCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Billing.Plan
  alias Storyarn.Drafts.{CloneEngine, Draft}
  alias Storyarn.Flows.Flow
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets.Sheet

  @default_draft_limit 2

  @doc """
  Creates a draft by cloning the source entity and all its children.
  Runs in a single transaction.
  """
  def create_draft(project_id, entity_type, source_entity_id, user_id, opts \\ [])
      when entity_type in ["sheet", "flow", "scene"] do
    with :ok <- check_draft_limit(project_id, user_id) do
      name = Keyword.get(opts, :name)
      run_in_transaction(project_id, entity_type, source_entity_id, user_id, name)
    end
  end

  defp run_in_transaction(project_id, entity_type, source_entity_id, user_id, name) do
    Repo.transaction(fn ->
      case do_create_draft(project_id, entity_type, source_entity_id, user_id, name) do
        {:ok, draft} -> draft
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp do_create_draft(project_id, entity_type, source_entity_id, user_id, name) do
    source_name = CloneEngine.get_source_name(entity_type, project_id, source_entity_id)

    with {:ok, source_name} <- require_source(source_name),
         baseline_ids <-
           CloneEngine.get_baseline_entity_ids(entity_type, project_id, source_entity_id),
         {:ok, draft} <-
           insert_draft(
             project_id,
             entity_type,
             source_entity_id,
             user_id,
             name || source_name <> " (Draft)",
             baseline_ids
           ),
         {:ok, _cloned} <- CloneEngine.clone(entity_type, project_id, source_entity_id, draft.id) do
      {:ok, Repo.preload(draft, :created_by)}
    end
  end

  defp require_source(nil), do: {:error, :source_not_found}
  defp require_source(name), do: {:ok, name}

  defp insert_draft(project_id, entity_type, source_entity_id, user_id, draft_name, baseline_ids) do
    %Draft{project_id: project_id, created_by_id: user_id}
    |> Draft.create_changeset(%{
      entity_type: entity_type,
      source_entity_id: source_entity_id,
      name: draft_name
    })
    |> Ecto.Changeset.put_change(:baseline_entity_ids, baseline_ids)
    |> Repo.insert()
  end

  @doc """
  Lists active drafts for a user in a project, enriched with source entity names.
  Each draft gets the virtual `source_name` field set (nil if the source is gone).
  """
  def list_my_drafts(project_id, user_id) do
    drafts =
      from(d in Draft,
        where:
          d.project_id == ^project_id and d.created_by_id == ^user_id and d.status == "active",
        order_by: [desc: d.last_edited_at],
        preload: [:created_by]
      )
      |> Repo.all()

    enrich_with_source_names(drafts)
  end

  defp enrich_with_source_names([]), do: []

  defp enrich_with_source_names(drafts) do
    # Group by entity_type, batch-load source names, merge back
    name_map =
      drafts
      |> Enum.group_by(& &1.entity_type)
      |> Enum.flat_map(fn {type, type_drafts} ->
        source_ids = Enum.map(type_drafts, & &1.source_entity_id) |> Enum.uniq()
        load_source_names(type, source_ids)
      end)
      |> Map.new()

    Enum.map(drafts, fn draft ->
      key = {draft.entity_type, draft.source_entity_id}
      source_name = Map.get(name_map, key)
      %{draft | source_name: source_name}
    end)
  end

  defp load_source_names("sheet", ids) do
    from(s in Sheet, where: s.id in ^ids, select: {s.id, s.name})
    |> Repo.all()
    |> Enum.map(fn {id, name} -> {{"sheet", id}, name} end)
  end

  defp load_source_names("flow", ids) do
    from(f in Flow, where: f.id in ^ids, select: {f.id, f.name})
    |> Repo.all()
    |> Enum.map(fn {id, name} -> {{"flow", id}, name} end)
  end

  defp load_source_names("scene", ids) do
    from(s in Scene, where: s.id in ^ids, select: {s.id, s.name})
    |> Repo.all()
    |> Enum.map(fn {id, name} -> {{"scene", id}, name} end)
  end

  @doc """
  Renames a draft.
  """
  def rename_draft(%Draft{} = draft, name) do
    draft
    |> Draft.rename_changeset(%{name: name})
    |> Repo.update()
  end

  @doc """
  Touches `last_edited_at` on a draft without loading it.
  Returns `:ok` if the draft was touched, `{:error, :not_found}` otherwise.
  """
  def touch_draft(draft_id) do
    now = TimeHelpers.now()

    case from(d in Draft, where: d.id == ^draft_id and d.status == "active")
         |> Repo.update_all(set: [last_edited_at: now]) do
      {n, _} when n > 0 -> :ok
      {0, _} -> {:error, :not_found}
    end
  end

  @doc """
  Gets a draft by ID with preloads. No ownership check — use `get_my_draft/2` for user-facing code.
  """
  def get_draft(draft_id) do
    Draft
    |> Repo.get(draft_id)
    |> Repo.preload([:created_by])
  end

  @doc """
  Gets a draft by ID, verifying it belongs to the given user within the given project.
  Returns nil if not found, not owned by the user, or not in the project.
  """
  def get_my_draft(draft_id, user_id, project_id) do
    from(d in Draft,
      where: d.id == ^draft_id and d.created_by_id == ^user_id and d.project_id == ^project_id,
      preload: [:created_by]
    )
    |> Repo.one()
  end

  @doc """
  Gets the cloned entity for a draft.
  """
  def get_draft_entity(%Draft{} = draft) do
    CloneEngine.get_draft_entity(draft.entity_type, draft.id)
  end

  @doc """
  Discards a draft and deletes the cloned entity.
  """
  def discard_draft(%Draft{status: "active"} = draft) do
    Repo.transaction(fn ->
      # Delete the cloned entity (cascade will handle children)
      CloneEngine.delete_draft_entity(draft.entity_type, draft.id)

      # Mark draft as discarded
      case draft |> Draft.discard_changeset() |> Repo.update() do
        {:ok, updated} -> updated
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  def discard_draft(%Draft{}), do: {:error, :not_active}

  @doc """
  Counts active drafts for a user in a project.
  """
  def count_active_drafts(project_id, user_id) do
    from(d in Draft,
      where: d.project_id == ^project_id and d.created_by_id == ^user_id and d.status == "active"
    )
    |> Repo.aggregate(:count)
  end

  @doc """
  Checks if a user can create another draft.
  """
  def can_create_draft?(project_id, user_id) do
    count_active_drafts(project_id, user_id) < max_active_drafts()
  end

  defp check_draft_limit(project_id, user_id) do
    if count_active_drafts(project_id, user_id) < max_active_drafts() do
      :ok
    else
      {:error, :draft_limit_reached}
    end
  end

  defp max_active_drafts do
    Plan.limit(Plan.default_plan(), :max_active_drafts_per_user) || @default_draft_limit
  end
end
