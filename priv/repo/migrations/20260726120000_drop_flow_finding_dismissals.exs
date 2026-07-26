defmodule Storyarn.Repo.Migrations.DropFlowFindingDismissals do
  use Ecto.Migration

  # Flow health is consolidated onto the sheets/scenes contract: one checker, a
  # flat list of issues, two consumers. Dismissals were never part of that
  # contract — neither sheets nor scenes have them — and they existed to anchor a
  # disposition to an exact finding occurrence, which is why the analysis engine
  # carried rule versions and evidence fingerprints. All of it goes together.
  #
  # A drop migration rather than deleting the original: `20260724120000` is
  # already applied on main and in every developer database, so removing the file
  # would leave a `schema_migrations` row with no migration behind it.
  #
  # `flows_id_project_id_index` is NOT dropped here: the original migration
  # created it as the composite-FK target, but other tables may rely on it and a
  # unique index on `(id, project_id)` is harmless. Dropping it belongs to
  # whoever proves it has no remaining referent.
  def up do
    drop_if_exists table(:flow_finding_dismissals)
  end

  # Irreversible by design: the rows are gone. `down` recreates the shape so a
  # rollback leaves a schema that matches the earlier migration, not the data.
  def down do
    create table(:flow_finding_dismissals) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false

      add :flow_id,
          references(:flows, with: [project_id: :project_id], on_delete: :delete_all),
          null: false

      add :finding_key, :string, null: false
      add :rule_id, :string, null: false
      add :rule_version, :integer, null: false
      add :evidence_fingerprint, :string, null: false
      add :reason_code, :string, null: false
      add :note, :text
      add :dismissed_by_id, references(:users, on_delete: :nilify_all)
      add :dismissed_at, :utc_datetime, null: false
      add :restored_by_id, references(:users, on_delete: :nilify_all)
      add :restored_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(
             :flow_finding_dismissals,
             [:flow_id, :finding_key, :rule_version, :evidence_fingerprint],
             where: "restored_at IS NULL",
             name: :flow_finding_dismissals_active_unique
           )
  end
end
