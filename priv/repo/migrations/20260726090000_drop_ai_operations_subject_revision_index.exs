defmodule Storyarn.Repo.Migrations.DropAiOperationsSubjectRevisionIndex do
  use Ecto.Migration

  # Added in Slice 7.2a for the explanation-ready badge and removed with it in
  # 7.1a.0. Its only query, `Results.readable_subject_revisions/3`, is gone, so the
  # index is write cost on every ai_operations insert for nothing.
  #
  # A drop migration rather than deleting the original: the original is already
  # applied on main and in every developer database, so removing the file would
  # leave a schema_migrations row with no migration behind it.
  def up do
    drop_if_exists index(:ai_operations, [:actor_id, :task_id, :subject_revision],
                     name: :ai_operations_actor_task_subject_revision_index
                   )
  end

  def down do
    create_if_not_exists index(:ai_operations, [:actor_id, :task_id, :subject_revision],
                           name: :ai_operations_actor_task_subject_revision_index
                         )
  end
end
