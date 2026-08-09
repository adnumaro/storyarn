defmodule Storyarn.Repo.Migrations.BackfillSnapshotClaimReconciliationSequence do
  use Ecto.Migration

  @disable_ddl_transaction true

  @batch_size 10_000
  @sequence "storyarn_snapshot_claim_reconciliation_seq"

  def up, do: backfill_batches()

  def down, do: :ok

  @doc false
  def batch_size, do: @batch_size

  @doc false
  def batch_sql(after_prefix \\ nil)

  def batch_sql(nil) do
    """
    WITH batch AS MATERIALIZED (
      SELECT object_prefix
      FROM snapshot_object_publication_claims
      WHERE reconciliation_sequence IS NULL
      ORDER BY object_prefix
      LIMIT $1
      FOR UPDATE
    ), bounds AS MATERIALIZED (
      SELECT min(object_prefix) AS first_prefix,
             max(object_prefix) AS last_prefix,
             count(*) AS selected_count
      FROM batch
    ), updated AS (
      UPDATE snapshot_object_publication_claims AS claim
      SET reconciliation_sequence = nextval('#{@sequence}'::regclass)
      FROM bounds
      WHERE claim.reconciliation_sequence IS NULL
        AND claim.object_prefix >= bounds.first_prefix
        AND claim.object_prefix <= bounds.last_prefix
      RETURNING claim.object_prefix
    )
    SELECT bounds.last_prefix,
           bounds.selected_count,
           count(updated.object_prefix) AS updated_count
    FROM bounds
    LEFT JOIN updated ON true
    GROUP BY bounds.last_prefix, bounds.selected_count
    """
  end

  def batch_sql(after_prefix) when is_binary(after_prefix) do
    """
    WITH batch AS MATERIALIZED (
      SELECT object_prefix
      FROM snapshot_object_publication_claims
      WHERE reconciliation_sequence IS NULL
        AND object_prefix > $2
      ORDER BY object_prefix
      LIMIT $1
      FOR UPDATE
    ), bounds AS MATERIALIZED (
      SELECT min(object_prefix) AS first_prefix,
             max(object_prefix) AS last_prefix,
             count(*) AS selected_count
      FROM batch
    ), updated AS (
      UPDATE snapshot_object_publication_claims AS claim
      SET reconciliation_sequence = nextval('#{@sequence}'::regclass)
      FROM bounds
      WHERE claim.reconciliation_sequence IS NULL
        AND claim.object_prefix >= bounds.first_prefix
        AND claim.object_prefix <= bounds.last_prefix
      RETURNING claim.object_prefix
    )
    SELECT bounds.last_prefix,
           bounds.selected_count,
           count(updated.object_prefix) AS updated_count
    FROM bounds
    LEFT JOIN updated ON true
    GROUP BY bounds.last_prefix, bounds.selected_count
    """
  end

  defp backfill_batches(after_prefix \\ nil) do
    params = if is_nil(after_prefix), do: [@batch_size], else: [@batch_size, after_prefix]

    case repo().query!(batch_sql(after_prefix), params, log: false).rows do
      [[nil, 0, 0]] ->
        :ok

      [[last_prefix, selected_count, selected_count]] ->
        backfill_batches(last_prefix)

      [[_last_prefix, _selected_count, _updated_count]] ->
        raise "snapshot claim reconciliation sequence backfill changed during a locked batch"
    end
  end
end
