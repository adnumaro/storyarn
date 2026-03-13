defmodule Storyarn.Drafts.MergeEngine do
  @moduledoc """
  Handles merging a draft back into its source entity.

  Strategy (v1): full replacement — the draft's state completely replaces the
  original. A named version of the original is created first as a safety net.

  Flow:
  1. Load original entity + draft entity
  2. Create pre-merge snapshot of original (safety net)
  3. Build snapshot from draft entity
  4. Apply snapshot to original via existing SnapshotBuilder.restore_snapshot
  5. Mark draft as merged
  6. Delete draft entities (keep draft record for history)
  """

  import Ecto.Query, warn: false
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Drafts.{CloneEngine, Draft}
  alias Storyarn.Repo
  alias Storyarn.Versioning

  @doc """
  Merges a draft into its source entity. Runs in a single transaction.

  Returns `{:ok, updated_entity}` or `{:error, reason}`.
  """
  def merge_draft(%Draft{status: "active"} = draft, user_id) do
    Repo.transaction(fn ->
      case do_merge(draft, user_id) do
        {:ok, entity} -> entity
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def merge_draft(%Draft{}, _user_id), do: {:error, :not_active}

  defp do_merge(draft, user_id) do
    builder = Versioning.get_builder!(draft.entity_type)

    with {:ok, original} <- load_original(draft),
         {:ok, draft_entity} <- load_draft_entity(draft),
         :ok <- create_pre_merge_snapshot(draft, original, user_id),
         snapshot <- builder.build_snapshot(draft_entity),
         {:ok, updated} <- builder.restore_snapshot(original, snapshot),
         :ok <- mark_as_merged(draft),
         :ok <- cleanup_draft_entities(draft) do
      create_post_merge_snapshot(draft, updated, user_id)
      {:ok, updated}
    end
  end

  @doc """
  Loads the original (non-draft, non-deleted) entity for a draft.
  Returns `{:ok, entity}` or `{:error, :source_not_found}`.
  """
  def load_original(draft) do
    schema = entity_schema(draft.entity_type)

    result =
      from(e in schema,
        where:
          e.id == ^draft.source_entity_id and
            e.project_id == ^draft.project_id and
            is_nil(e.deleted_at) and
            is_nil(e.draft_id)
      )
      |> Repo.one()

    case result do
      nil -> {:error, :source_not_found}
      entity -> {:ok, entity}
    end
  end

  defp load_draft_entity(draft) do
    case CloneEngine.get_draft_entity(draft.entity_type, draft.id) do
      nil -> {:error, :draft_entity_not_found}
      entity -> {:ok, entity}
    end
  end

  defp create_pre_merge_snapshot(draft, original, user_id) do
    case Versioning.create_version(
           draft.entity_type,
           original,
           draft.project_id,
           user_id,
           title: dgettext("drafts", "Before merge from draft"),
           is_auto: false
         ) do
      {:ok, _version} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_post_merge_snapshot(draft, updated_entity, user_id) do
    Versioning.create_version(
      draft.entity_type,
      updated_entity,
      draft.project_id,
      user_id,
      title: dgettext("drafts", "Merged from draft"),
      is_auto: false
    )
  end

  defp mark_as_merged(draft) do
    with {:ok, changeset} <- Draft.merge_changeset(draft),
         {:ok, _} <- Repo.update(changeset) do
      :ok
    end
  end

  defp cleanup_draft_entities(draft) do
    CloneEngine.delete_draft_entity(draft.entity_type, draft.id)
    :ok
  end

  defp entity_schema("sheet"), do: Storyarn.Sheets.Sheet
  defp entity_schema("flow"), do: Storyarn.Flows.Flow
  defp entity_schema("scene"), do: Storyarn.Scenes.Scene
end
