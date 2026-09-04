defmodule Storyarn.Repo.Migrations.PinWorkspaceSnapshotImportNamespace do
  use Ecto.Migration

  def change do
    alter table(:workspace_snapshot_imports) do
      # Existing owners have unknown provenance. Never backfill from the current
      # provider: the import workflow retains them and fails closed instead.
      add :provider_namespace_fingerprint, :string
    end

    create constraint(
             :workspace_snapshot_imports,
             :workspace_snapshot_imports_provider_namespace_check,
             check:
               "provider_namespace_fingerprint IS NULL OR provider_namespace_fingerprint ~ '^[0-9a-f]{64}$'"
           )
  end
end
