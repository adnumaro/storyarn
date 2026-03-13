defmodule Storyarn.Drafts do
  @moduledoc """
  The Drafts context.

  Manages draft copies of flows, sheets, and scenes for private experimentation.
  Only the creator can see and edit their drafts.
  """

  alias Storyarn.Drafts.{DiffSummary, DraftCrud, MergeEngine}

  defdelegate create_draft(project_id, entity_type, source_entity_id, user_id, opts \\ []),
    to: DraftCrud

  defdelegate list_my_drafts(project_id, user_id), to: DraftCrud
  defdelegate get_draft(draft_id), to: DraftCrud
  defdelegate get_my_draft(draft_id, user_id, project_id), to: DraftCrud
  defdelegate get_draft_entity(draft), to: DraftCrud
  defdelegate discard_draft(draft), to: DraftCrud
  defdelegate rename_draft(draft, name), to: DraftCrud
  defdelegate touch_draft(draft_id), to: DraftCrud
  defdelegate can_create_draft?(project_id, user_id), to: DraftCrud

  defdelegate merge_draft(draft, user_id), to: MergeEngine
  defdelegate build_merge_summary(draft), to: DiffSummary, as: :build_summary
end
