defmodule Storyarn.Drafts.DiffSummary do
  @moduledoc """
  Builds a comparison summary between a draft entity and its original.

  Uses existing SnapshotBuilder.build_snapshot/1 and diff_snapshots/2 to detect
  changes. Also checks if the original has diverged (new versions since fork).
  """

  alias Storyarn.Drafts.{CloneEngine, Draft}
  alias Storyarn.Drafts.MergeEngine
  alias Storyarn.Versioning
  alias Storyarn.Versioning.SnapshotDiff

  @type t :: %{
          draft_changes: String.t(),
          original_versions_since_fork: non_neg_integer()
        }

  @doc """
  Builds a merge summary for the given draft.

  Returns `{:ok, summary}` or `{:error, reason}`.
  """
  def build_summary(%Draft{status: "active"} = draft) do
    builder = Versioning.get_builder!(draft.entity_type)

    with {:ok, original} <- MergeEngine.load_original(draft),
         draft_entity when not is_nil(draft_entity) <-
           CloneEngine.get_draft_entity(draft.entity_type, draft.id) do
      original_snapshot = builder.build_snapshot(original)
      draft_snapshot = builder.build_snapshot(draft_entity)

      diff_text =
        draft.entity_type
        |> SnapshotDiff.diff(original_snapshot, draft_snapshot)
        |> SnapshotDiff.format_summary()

      versions_since = count_versions_since_fork(draft)

      {:ok,
       %{
         draft_changes: diff_text,
         original_versions_since_fork: versions_since
       }}
    else
      {:error, :source_not_found} -> {:error, :not_found}
      nil -> {:error, :not_found}
    end
  end

  def build_summary(%Draft{}), do: {:error, :not_active}

  defp count_versions_since_fork(draft) do
    Versioning.count_versions_since(draft.entity_type, draft.source_entity_id, draft.inserted_at)
  end
end
