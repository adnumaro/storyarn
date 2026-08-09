defmodule Storyarn.Repo.Migrations.IndexSnapshotClaimReconciliationSequence do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    drop_if_exists unique_index(
                     :snapshot_object_publication_claims,
                     [:reconciliation_sequence],
                     concurrently: true
                   )

    create unique_index(
             :snapshot_object_publication_claims,
             [:reconciliation_sequence],
             concurrently: true
           )
  end

  def down do
    drop_if_exists unique_index(
                     :snapshot_object_publication_claims,
                     [:reconciliation_sequence],
                     concurrently: true
                   )
  end
end
