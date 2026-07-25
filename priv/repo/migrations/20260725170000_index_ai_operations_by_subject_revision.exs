defmodule Storyarn.Repo.Migrations.IndexAiOperationsBySubjectRevision do
  use Ecto.Migration

  # The analysis panel asks "which of these findings already have an explanation I
  # paid for", which is one lookup over (actor, task, many revisions). The existing
  # indexes cover the idempotency key and the timeline, neither of which serves a
  # subject_revision IN (...) filter, so it would have been a sequential scan of
  # every operation in the table on every panel render.
  def change do
    create index(:ai_operations, [:actor_id, :task_id, :subject_revision],
             name: :ai_operations_actor_task_subject_revision_index
           )
  end
end
