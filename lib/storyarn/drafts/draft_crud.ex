defmodule Storyarn.Drafts.DraftCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Billing.Plan
  alias Storyarn.Drafts.{CloneEngine, Draft}
  alias Storyarn.Repo

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
         {:ok, draft} <-
           insert_draft(
             project_id,
             entity_type,
             source_entity_id,
             user_id,
             name || source_name <> " (Draft)"
           ),
         {:ok, _cloned} <- CloneEngine.clone(entity_type, project_id, source_entity_id, draft.id) do
      {:ok, Repo.preload(draft, :created_by)}
    end
  end

  defp require_source(nil), do: {:error, :source_not_found}
  defp require_source(name), do: {:ok, name}

  defp insert_draft(project_id, entity_type, source_entity_id, user_id, draft_name) do
    %Draft{project_id: project_id, created_by_id: user_id}
    |> Draft.create_changeset(%{
      entity_type: entity_type,
      source_entity_id: source_entity_id,
      name: draft_name
    })
    |> Repo.insert()
  end

  @doc """
  Lists active drafts for a user in a project.
  """
  def list_my_drafts(project_id, user_id) do
    from(d in Draft,
      where: d.project_id == ^project_id and d.created_by_id == ^user_id and d.status == "active",
      order_by: [desc: d.inserted_at],
      preload: [:created_by]
    )
    |> Repo.all()
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
  Gets a draft by ID, verifying it belongs to the given user.
  Returns nil if not found or not owned by the user.
  """
  def get_my_draft(draft_id, user_id) do
    from(d in Draft,
      where: d.id == ^draft_id and d.created_by_id == ^user_id,
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
    Plan.limit(Plan.default_plan(), :max_active_drafts_per_user) || 2
  end
end
