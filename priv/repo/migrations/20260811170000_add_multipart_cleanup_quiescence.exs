defmodule Storyarn.Repo.Migrations.AddMultipartCleanupQuiescence do
  use Ecto.Migration

  @constraint :storage_cleanup_requests_multipart_quiescence

  def up do
    alter table(:storage_cleanup_requests) do
      add :multipart_quiescence_started_at, :utc_datetime
      add :multipart_quiescence_not_before, :utc_datetime
    end

    create constraint(:storage_cleanup_requests, @constraint,
             check: """
             (multipart_quiescence_started_at IS NULL AND multipart_quiescence_not_before IS NULL) OR
             (multipart_quiescence_started_at IS NOT NULL AND multipart_quiescence_not_before IS NOT NULL AND
              multipart_quiescence_not_before >= multipart_quiescence_started_at)
             """
           )
  end

  def down do
    drop constraint(:storage_cleanup_requests, @constraint)

    alter table(:storage_cleanup_requests) do
      remove :multipart_quiescence_not_before
      remove :multipart_quiescence_started_at
    end
  end
end
