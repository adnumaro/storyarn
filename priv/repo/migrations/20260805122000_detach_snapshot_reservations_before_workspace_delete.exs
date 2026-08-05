defmodule Storyarn.Repo.Migrations.DetachSnapshotReservationsBeforeWorkspaceDelete do
  use Ecto.Migration

  def change do
    execute(
      """
      CREATE FUNCTION storyarn_detach_snapshot_reservations_before_workspace_delete()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        UPDATE workspace_storage_reservations
        SET workspace_id = NULL, project_id = NULL, project_snapshot_id = NULL
        WHERE workspace_id = OLD.id;

        RETURN OLD;
      END;
      $$
      """,
      "DROP FUNCTION IF EXISTS storyarn_detach_snapshot_reservations_before_workspace_delete() CASCADE"
    )

    execute(
      """
      CREATE TRIGGER workspaces_detach_snapshot_reservations
      BEFORE DELETE ON workspaces
      FOR EACH ROW
      EXECUTE FUNCTION storyarn_detach_snapshot_reservations_before_workspace_delete()
      """,
      "DROP TRIGGER IF EXISTS workspaces_detach_snapshot_reservations ON workspaces"
    )
  end
end
