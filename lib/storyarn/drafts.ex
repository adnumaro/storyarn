defmodule Storyarn.Drafts do
  @moduledoc """
  The Drafts context.

  Manages draft copies of flows, sheets, and scenes for private experimentation.
  Only the creator can see and edit their drafts.
  """

  alias Storyarn.Drafts.DraftCrud

  defdelegate create_draft(project_id, entity_type, source_entity_id, user_id, opts \\ []),
    to: DraftCrud

  defdelegate list_my_drafts(project_id, user_id), to: DraftCrud
  defdelegate get_draft(draft_id), to: DraftCrud
  defdelegate get_my_draft(draft_id, user_id), to: DraftCrud
  defdelegate get_draft_entity(draft), to: DraftCrud
  defdelegate discard_draft(draft), to: DraftCrud
  defdelegate can_create_draft?(project_id, user_id), to: DraftCrud
end
