defmodule Storyarn.Repo.Migrations.CreateLocalizationTranslationRuns do
  use Ecto.Migration

  def change do
    create table(:localization_translation_runs) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :requested_by_id, references(:users, on_delete: :nilify_all)
      add :oban_job_id, references(:oban_jobs, type: :bigint, on_delete: :nilify_all)
      add :target_locale, :string, size: 10, null: false
      add :source_type, :string
      add :text_status, :string, null: false, default: "pending"
      add :status, :string, null: false, default: "queued"
      add :total_count, :integer, null: false, default: 0
      add :processed_count, :integer, null: false, default: 0
      add :translated_count, :integer, null: false, default: 0
      add :failed_count, :integer, null: false, default: 0
      add :error, :text
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :cancelled_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:localization_translation_runs, [:project_id, :target_locale, :inserted_at],
             name: :localization_runs_project_locale_inserted_idx
           )

    create index(:localization_translation_runs, [:oban_job_id],
             name: :localization_runs_oban_job_idx
           )

    create unique_index(:localization_translation_runs, [:project_id, :target_locale],
             where: "status IN ('queued', 'running')",
             name: :localization_translation_runs_one_active
           )

    create constraint(:localization_translation_runs, :localization_runs_total_count_non_negative,
             check: "total_count >= 0"
           )

    create constraint(
             :localization_translation_runs,
             :localization_runs_processed_count_non_negative,
             check: "processed_count >= 0"
           )

    create constraint(
             :localization_translation_runs,
             :localization_runs_translated_count_non_negative,
             check: "translated_count >= 0"
           )

    create constraint(
             :localization_translation_runs,
             :localization_runs_failed_count_non_negative,
             check: "failed_count >= 0"
           )
  end
end
