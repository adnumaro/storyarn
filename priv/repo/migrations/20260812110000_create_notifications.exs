defmodule Storyarn.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications) do
      add :recipient_id, references(:users, on_delete: :delete_all), null: false
      add :actor_id, references(:users, on_delete: :nilify_all)
      add :project_id, references(:projects, on_delete: :delete_all)

      add :kind, :string, null: false, size: 64
      add :entity_type, :string, size: 64
      add :entity_id, :bigint
      add :entity_name, :string, size: 255
      add :status, :string, size: 32
      add :dedupe_key, :string, null: false, size: 200
      add :read_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create constraint(:notifications, :notifications_actor_recipient_check,
             check: "actor_id IS NULL OR actor_id <> recipient_id"
           )

    create constraint(:notifications, :notifications_entity_identity_check,
             check:
               "(entity_type IS NULL AND entity_id IS NULL) OR " <>
                 "(entity_type IS NOT NULL AND entity_id IS NOT NULL AND entity_id > 0)"
           )

    create constraint(:notifications, :notifications_project_scope_check,
             check:
               "entity_type IS NULL OR " <>
                 "entity_type NOT IN (" <>
                 "'project_snapshot', 'project_import', 'localization_batch', " <>
                 "'sheet', 'flow', 'scene', 'localization_language'" <>
                 ") OR project_id IS NOT NULL"
           )

    create constraint(:notifications, :notifications_status_check,
             check: "status IS NULL OR status IN ('success', 'failure')"
           )

    create constraint(:notifications, :notifications_kind_not_blank,
             check: "length(trim(kind)) > 0"
           )

    create constraint(:notifications, :notifications_dedupe_key_not_blank,
             check: "length(trim(dedupe_key)) > 0"
           )

    create unique_index(:notifications, [:recipient_id, :dedupe_key],
             name: :notifications_recipient_dedupe_index
           )

    create index(:notifications, [:recipient_id, :inserted_at, :id],
             name: :notifications_recipient_feed_index
           )

    create index(:notifications, [:recipient_id, :inserted_at, :id],
             where: "read_at IS NULL",
             name: :notifications_recipient_unread_index
           )

    create index(:notifications, [:actor_id])
    create index(:notifications, [:project_id])
  end
end
