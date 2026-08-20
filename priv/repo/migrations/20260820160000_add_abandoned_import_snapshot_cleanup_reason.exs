defmodule Storyarn.Repo.Migrations.AddAbandonedImportSnapshotCleanupReason do
  use Ecto.Migration

  def up do
    replace_identity_constraint(include_abandoned_import?: true)
  end

  def down do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM snapshot_cleanup_intents
        WHERE reason = 'abandoned_import'
      ) THEN
        RAISE EXCEPTION
          'cannot remove abandoned_import cleanup support while matching intents exist';
      END IF;
    END
    $$;
    """)

    replace_identity_constraint(include_abandoned_import?: false)
  end

  defp replace_identity_constraint(opts) do
    reasons =
      if Keyword.fetch!(opts, :include_abandoned_import?) do
        "'user_delete', 'retention', 'expired_build', 'abandoned_import', " <>
          "'project_hard_delete', 'workspace_hard_delete'"
      else
        "'user_delete', 'retention', 'expired_build', " <>
          "'project_hard_delete', 'workspace_hard_delete'"
      end

    drop constraint(:snapshot_cleanup_intents, :snapshot_cleanup_intents_identity)

    create constraint(:snapshot_cleanup_intents, :snapshot_cleanup_intents_identity,
             check: """
             workspace_id_snapshot > 0 AND project_id_snapshot > 0 AND
             project_snapshot_id_snapshot > 0 AND deletion_generation > 0 AND
             mode = 'full' AND
             origin IN ('user', 'daily', 'pre_restore', 'post_restore') AND
             reason IN (#{reasons}) AND
             authority_kind IN ('user', 'system') AND
             ((authority_kind = 'user' AND authority_actor_id IS NOT NULL AND
               authority_actor_id > 0) OR
              (authority_kind = 'system' AND authority_actor_id IS NULL)) AND
             ready_prefix ~ ('^projects/' || project_id_snapshot ||
               '/snapshots/archives/v2/ready/[A-Za-z0-9_-]{16}$') AND
             staging_prefix ~ ('^projects/' || project_id_snapshot ||
               '/snapshots/archives/v2/staging/[A-Za-z0-9_-]{16}$') AND
             inventory_digest ~ '^[0-9a-f]{64}$' AND object_count > 0 AND
             estimated_cleanup_bytes >= 0 AND cardinality(storage_keys) = object_count AND
             status IN ('pending', 'processing', 'retrying', 'completed', 'terminal') AND
             retry_count >= 0 AND processing_generation >= 0 AND
             required_delete_passes = (CASE WHEN reason = 'expired_build' THEN 2 ELSE 1 END) AND
             completed_delete_passes >= 0 AND
             completed_delete_passes <= required_delete_passes AND
             ((required_delete_passes = 1 AND next_delete_pass_at IS NULL) OR
              (required_delete_passes = 2 AND
               ((completed_delete_passes = 0 AND next_delete_pass_at IS NULL) OR
                (completed_delete_passes > 0 AND next_delete_pass_at IS NOT NULL)))) AND
             ((status = 'completed' AND cardinality(remaining_storage_keys) = 0 AND
               completed_at IS NOT NULL) OR
              (status = 'terminal' AND cardinality(remaining_storage_keys) > 0 AND
               terminal_at IS NOT NULL) OR
              (status IN ('pending', 'processing', 'retrying') AND
               cardinality(remaining_storage_keys) > 0 AND completed_at IS NULL AND
               terminal_at IS NULL)) AND
             ((status = 'completed' AND completed_delete_passes = required_delete_passes) OR
              (status <> 'completed' AND completed_delete_passes < required_delete_passes))
             """
           )
  end
end
