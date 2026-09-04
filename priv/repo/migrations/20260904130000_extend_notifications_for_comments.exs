defmodule Storyarn.Repo.Migrations.ExtendNotificationsForComments do
  use Ecto.Migration

  def up do
    drop constraint(:notifications, :notifications_project_scope_check)

    create constraint(:notifications, :notifications_project_scope_check,
             check:
               "entity_type IS NULL OR " <>
                 "entity_type NOT IN (" <>
                 "'project_snapshot', 'project_import', 'localization_batch', " <>
                 "'sheet', 'flow', 'scene', 'localization_language', 'comment'" <>
                 ") OR project_id IS NOT NULL"
           )
  end

  def down do
    drop constraint(:notifications, :notifications_project_scope_check)

    create constraint(:notifications, :notifications_project_scope_check,
             check:
               "entity_type IS NULL OR " <>
                 "entity_type NOT IN (" <>
                 "'project_snapshot', 'project_import', 'localization_batch', " <>
                 "'sheet', 'flow', 'scene', 'localization_language'" <>
                 ") OR project_id IS NOT NULL"
           )
  end
end
