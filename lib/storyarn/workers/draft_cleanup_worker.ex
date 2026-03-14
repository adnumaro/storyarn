defmodule Storyarn.Workers.DraftCleanupWorker do
  @moduledoc """
  Oban cron worker that cleans up orphaned entities from merged/discarded drafts.

  Runs daily at 5 AM UTC. Finds drafts that are merged or discarded and still have
  cloned entities lingering (orphans from incomplete cleanup), then deletes them.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  import Ecto.Query, warn: false

  alias Storyarn.Drafts.{CloneEngine, Draft}
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    cleanup_orphaned_entities()
    :ok
  end

  defp cleanup_orphaned_entities do
    # Find merged/discarded drafts older than 1 day (give recent operations time to complete)
    cutoff = DateTime.add(TimeHelpers.now(), -86_400, :second)

    orphaned_drafts =
      from(d in Draft,
        where: d.status in ["merged", "discarded"],
        where: d.updated_at < ^cutoff
      )
      |> Repo.all()

    Enum.each(orphaned_drafts, fn draft ->
      try do
        cleanup_draft_entity(draft)
      rescue
        e ->
          Logger.error("Draft cleanup failed for draft #{draft.id}: #{Exception.message(e)}")
      end
    end)

    if orphaned_drafts != [] do
      Logger.info("Draft cleanup processed #{length(orphaned_drafts)} drafts")
    end
  end

  defp cleanup_draft_entity(draft) do
    {count, _} = CloneEngine.delete_draft_entity(draft.entity_type, draft.id)

    if count > 0 do
      Logger.info(
        "Cleaned up #{count} orphaned #{draft.entity_type} entity for draft #{draft.id}"
      )
    end
  end
end
