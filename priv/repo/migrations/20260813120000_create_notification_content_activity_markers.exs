defmodule Storyarn.Repo.Migrations.CreateNotificationContentActivityMarkers do
  use Ecto.Migration

  def change do
    create table(:notification_content_activity_markers) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :entity_type, :string, null: false, size: 64
      add :entity_id, :bigint, null: false
      add :action, :string, null: false, size: 16

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create constraint(
             :notification_content_activity_markers,
             :notification_content_activity_markers_entity_check,
             check:
               "entity_type IN ('sheet', 'flow', 'scene', 'localization_language') " <>
                 "AND entity_id > 0"
           )

    create constraint(
             :notification_content_activity_markers,
             :notification_content_activity_markers_action_check,
             check: "action IN ('created', 'deleted')"
           )

    create unique_index(
             :notification_content_activity_markers,
             [:project_id, :entity_type, :entity_id, :action],
             name: :notification_content_activity_markers_identity_index
           )
  end
end
