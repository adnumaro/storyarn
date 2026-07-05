defmodule Storyarn.Repo.Migrations.AddLocalizedTextsBatchTranslationCursorIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    create_if_not_exists index(:localized_texts, [:project_id, :locale_code, :status, :id],
                           name: :localized_texts_batch_translation_cursor_index,
                           concurrently: true
                         )
  end

  def down do
    drop_if_exists index(:localized_texts, [:project_id, :locale_code, :status, :id],
                     name: :localized_texts_batch_translation_cursor_index,
                     concurrently: true
                   )
  end
end
