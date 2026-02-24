defmodule Mix.Tasks.MigrateZoneActionTypes do
  @moduledoc """
  Migrates legacy zone action_types to the new model:

  - `navigate` → `none` (target_type/target_id preserved)
  - `event` → `none` (logged for manual review)

  Usage:
    mix migrate_zone_action_types          # execute migration
    mix migrate_zone_action_types --dry-run # preview changes only
  """

  use Mix.Task

  import Ecto.Query

  alias Storyarn.Repo
  alias Storyarn.Scenes.SceneZone

  @shortdoc "Migrate legacy zone action_types (navigate/event → none)"

  @impl Mix.Task
  def run(args) do
    dry_run? = "--dry-run" in args

    Mix.Task.run("app.start")

    navigate_zones = list_zones_by_action_type("navigate")
    event_zones = list_zones_by_action_type("event")

    Mix.shell().info("Found #{length(navigate_zones)} navigate zones")
    Mix.shell().info("Found #{length(event_zones)} event zones")

    if dry_run? do
      Mix.shell().info("\n[DRY RUN] No changes will be made.\n")

      for zone <- navigate_zones do
        Mix.shell().info(
          "  Would migrate zone #{zone.id} (#{zone.name}): navigate → none " <>
            "(target: #{zone.target_type}/#{zone.target_id})"
        )
      end

      for zone <- event_zones do
        event_name = (zone.action_data || %{})["event_name"] || "?"

        Mix.shell().info(
          "  Would migrate zone #{zone.id} (#{zone.name}): event → none " <>
            "(event_name: #{event_name}) [REVIEW: event data lost]"
        )
      end
    else
      migrated =
        Repo.transaction(fn ->
          nav_count = migrate_zones(navigate_zones, "navigate")
          event_count = migrate_zones(event_zones, "event")
          nav_count + event_count
        end)

      case migrated do
        {:ok, count} ->
          Mix.shell().info("\nMigrated #{count} zones successfully.")

        {:error, reason} ->
          Mix.shell().error("\nMigration failed: #{inspect(reason)}")
      end
    end
  end

  defp list_zones_by_action_type(action_type) do
    from(z in SceneZone,
      where: z.action_type == ^action_type,
      order_by: [asc: z.id]
    )
    |> Repo.all()
  end

  defp migrate_zones(zones, original_type) do
    Enum.reduce(zones, 0, fn zone, count ->
      attrs = %{action_type: "none", action_data: %{}}

      case zone
           |> Ecto.Changeset.change(attrs)
           |> Repo.update() do
        {:ok, _} ->
          log_event_migration(zone, original_type)
          count + 1

        {:error, changeset} ->
          Mix.shell().error("  Failed to migrate zone #{zone.id}: #{inspect(changeset.errors)}")

          count
      end
    end)
  end

  defp log_event_migration(zone, "event") do
    event_name = (zone.action_data || %{})["event_name"] || "?"
    Mix.shell().info("  Migrated event zone #{zone.id} (#{zone.name}, event: #{event_name})")
  end

  defp log_event_migration(_zone, _type), do: :ok
end
