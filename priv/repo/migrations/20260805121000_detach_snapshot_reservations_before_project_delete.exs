defmodule Storyarn.Repo.Migrations.DetachSnapshotReservationsBeforeProjectDelete do
  use Ecto.Migration

  def change do
    execute(
      """
      CREATE FUNCTION storyarn_detach_snapshot_reservations_before_project_delete()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        UPDATE workspace_storage_reservations
        SET project_id = NULL, project_snapshot_id = NULL
        WHERE project_id = OLD.id;

        RETURN OLD;
      END;
      $$
      """,
      "DROP FUNCTION IF EXISTS storyarn_detach_snapshot_reservations_before_project_delete() CASCADE"
    )

    execute(
      """
      CREATE TRIGGER projects_detach_snapshot_reservations
      BEFORE DELETE ON projects
      FOR EACH ROW
      EXECUTE FUNCTION storyarn_detach_snapshot_reservations_before_project_delete()
      """,
      "DROP TRIGGER IF EXISTS projects_detach_snapshot_reservations ON projects"
    )
  end
end
