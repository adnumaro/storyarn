defmodule Storyarn.Repo.Migrations.CreateLocalizationTables do
  use Ecto.Migration

  def change do
    # =========================================================================
    # Table 1: project_languages
    # =========================================================================
    create table(:project_languages) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :locale_code, :string, size: 10, null: false
      add :name, :string, null: false
      add :is_source, :boolean, default: false, null: false
      add :position, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:project_languages, [:project_id, :locale_code])

    create unique_index(:project_languages, [:project_id],
      where: "is_source = true",
      name: :project_languages_one_source
    )

    create index(:project_languages, [:project_id])

    # =========================================================================
    # Table 2: localized_texts
    # =========================================================================
    create table(:localized_texts) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :source_type, :string, null: false
      add :source_id, :integer, null: false
      add :source_field, :string, null: false
      add :source_text, :text
      add :source_text_hash, :string, size: 64
      add :locale_code, :string, size: 10, null: false
      add :translated_text, :text
      add :status, :string, default: "pending", null: false
      add :vo_status, :string, default: "none", null: false
      add :vo_asset_id, references(:assets, on_delete: :nilify_all)
      add :translator_notes, :text
      add :reviewer_notes, :text
      add :speaker_sheet_id, references(:sheets, on_delete: :nilify_all)
      add :word_count, :integer
      add :machine_translated, :boolean, default: false, null: false
      add :last_translated_at, :utc_datetime
      add :last_reviewed_at, :utc_datetime
      add :translated_by_id, references(:users, on_delete: :nilify_all)
      add :reviewed_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:localized_texts,
      [:source_type, :source_id, :source_field, :locale_code],
      name: :localized_texts_source_locale_unique
    )

    create index(:localized_texts, [:project_id, :locale_code, :status])

    create index(:localized_texts, [:project_id, :locale_code],
      where: "status != 'final'",
      name: :localized_texts_incomplete
    )

    create index(:localized_texts, [:speaker_sheet_id, :locale_code])
    create index(:localized_texts, [:source_type, :source_id])

    # =========================================================================
    # Table 3: localization_glossary_entries
    # =========================================================================
    create table(:localization_glossary_entries) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :source_term, :string, null: false
      add :source_locale, :string, size: 10, null: false
      add :target_term, :string
      add :target_locale, :string, size: 10, null: false
      add :context, :text
      add :do_not_translate, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:localization_glossary_entries,
      [:project_id, :source_term, :source_locale, :target_locale],
      name: :glossary_entries_unique
    )

    create index(:localization_glossary_entries, [:project_id])

    # =========================================================================
    # Table 4: translation_provider_configs
    # =========================================================================
    create table(:translation_provider_configs) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :provider, :string, null: false, default: "deepl"
      add :api_key_encrypted, :binary
      add :api_endpoint, :string
      add :settings, :map, default: %{}
      add :is_active, :boolean, default: true, null: false
      add :deepl_glossary_ids, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:translation_provider_configs, [:project_id, :provider])
  end
end
