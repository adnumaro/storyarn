defmodule Storyarn.Repo.Migrations.HardenLocalizationWorkflow do
  use Ecto.Migration

  def up do
    alter table(:localized_texts) do
      add :translated_source_hash, :string, size: 64
      add :lock_version, :integer, null: false, default: 1
    end

    execute("""
    UPDATE localized_texts
    SET translated_source_hash = source_text_hash
    WHERE NULLIF(BTRIM(translated_text), '') IS NOT NULL
    """)

    execute("""
    UPDATE localized_texts
    SET status = CASE
      WHEN NULLIF(BTRIM(translated_text), '') IS NULL THEN 'pending'
      ELSE 'review'
    END
    WHERE status = 'final'
      AND (
        NULLIF(BTRIM(translated_text), '') IS NULL
        OR source_text_hash IS NULL
        OR translated_source_hash IS NULL
      )
    """)

    create constraint(:localized_texts, :localized_texts_final_requires_current_translation,
             check: """
             status <> 'final' OR (
               NULLIF(BTRIM(translated_text), '') IS NOT NULL
               AND translated_source_hash = source_text_hash
             )
             """
           )

    create index(:localized_texts, [:project_id, :locale_code, :translated_source_hash],
             name: :localized_texts_staleness_index
           )

    alter table(:project_languages) do
      add :archived_at, :utc_datetime
    end

    create index(:project_languages, [:project_id, :archived_at])
  end

  def down do
    drop index(:project_languages, [:project_id, :archived_at])

    alter table(:project_languages) do
      remove :archived_at
    end

    drop index(:localized_texts, [:project_id, :locale_code, :translated_source_hash],
           name: :localized_texts_staleness_index
         )

    drop constraint(:localized_texts, :localized_texts_final_requires_current_translation)

    alter table(:localized_texts) do
      remove :lock_version
      remove :translated_source_hash
    end
  end
end
