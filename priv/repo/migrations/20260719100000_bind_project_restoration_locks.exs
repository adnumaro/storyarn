defmodule Storyarn.Repo.Migrations.BindProjectRestorationLocks do
  use Ecto.Migration

  def up do
    alter table(:projects) do
      add :restoration_token, :uuid
      add :restoration_claimed_by_job_id, :bigint

      add :restoration_snapshot_id,
          references(:project_snapshots, on_delete: :restrict)
    end

    create index(:projects, [:restoration_snapshot_id])

    # Never silently clear a legacy lock or leave a legacy restore job able to
    # run after this migration. ALTER TABLE holds an ACCESS EXCLUSIVE lock on
    # projects until this transaction commits: old releases either completed
    # their lock write before this check (and are detected here), or their
    # write resumes after the new consistency constraint exists and fails.
    #
    # New releases enqueue onto :project_restores, a queue old releases do not
    # poll, so token-bound jobs remain fenced throughout a rolling deploy.
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM projects
        WHERE restoration_in_progress = TRUE
      ) OR EXISTS (
        SELECT 1
        FROM oban_jobs
        WHERE worker = 'Storyarn.Workers.RestoreProjectWorker'
          AND state IN ('available', 'scheduled', 'executing', 'retryable')
      ) THEN
        RAISE EXCEPTION
          'cannot bind project restoration locks while legacy restores are active or queued';
      END IF;
    END
    $$;
    """)

    create constraint(:projects, :projects_restoration_lock_consistency,
             check: """
             (
               restoration_in_progress = TRUE
               AND restoration_started_by_id IS NOT NULL
               AND restoration_started_at IS NOT NULL
               AND restoration_token IS NOT NULL
               AND (
                 restoration_claimed_by_job_id IS NULL
                 OR restoration_claimed_by_job_id > 0
               )
               AND restoration_snapshot_id IS NOT NULL
             )
             OR
             (
               restoration_in_progress = FALSE
               AND restoration_started_by_id IS NULL
               AND restoration_started_at IS NULL
               AND restoration_token IS NULL
               AND restoration_claimed_by_job_id IS NULL
               AND restoration_snapshot_id IS NULL
             )
             """
           )
  end

  def down do
    drop constraint(:projects, :projects_restoration_lock_consistency)

    alter table(:projects) do
      remove :restoration_snapshot_id
      remove :restoration_claimed_by_job_id
      remove :restoration_token
    end
  end
end
