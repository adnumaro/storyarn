defmodule Storyarn.Repo.Migrations.CreateFlowFindingDismissals do
  use Ecto.Migration

  @reason_codes ~w(intentional_design rule_not_applicable missing_context incorrect_detection duplicate_finding other)

  def change do
    create table(:flow_finding_dismissals) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :flow_id, references(:flows, on_delete: :delete_all), null: false

      add :finding_key, :string, null: false, size: 500
      add :rule_id, :string, null: false, size: 100
      add :rule_version, :integer, null: false
      add :evidence_fingerprint, :string, null: false, size: 64

      add :reason_code, :string, null: false, size: 40
      add :note, :string, size: 2000

      add :dismissed_by_id, references(:users, on_delete: :nilify_all)
      add :restored_at, :utc_datetime
      add :restored_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create constraint(
             :flow_finding_dismissals,
             :flow_finding_dismissals_reason_code_check,
             check: "reason_code IN ('#{Enum.join(@reason_codes, "', '")}')"
           )

    create constraint(
             :flow_finding_dismissals,
             :flow_finding_dismissals_other_requires_note_check,
             check: "reason_code != 'other' OR (note IS NOT NULL AND length(trim(note)) > 0)"
           )

    create constraint(
             :flow_finding_dismissals,
             :flow_finding_dismissals_restore_pair_check,
             check:
               "(restored_at IS NULL AND restored_by_id IS NULL) OR (restored_at IS NOT NULL)"
           )

    # One ACTIVE dismissal per exact finding occurrence; restore keeps history.
    # Concurrent dismiss requests collapse onto this partial unique index.
    create unique_index(
             :flow_finding_dismissals,
             [:flow_id, :finding_key, :rule_version, :evidence_fingerprint],
             where: "restored_at IS NULL",
             name: :flow_finding_dismissals_active_idx
           )

    create index(:flow_finding_dismissals, [:project_id])
    create index(:flow_finding_dismissals, [:flow_id])
    create index(:flow_finding_dismissals, [:dismissed_by_id])
    create index(:flow_finding_dismissals, [:restored_by_id])
  end
end
