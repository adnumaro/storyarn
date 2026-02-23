defmodule Mix.Tasks.MigrateInteractionToScene do
  @moduledoc """
  Migrates interaction node data to flow scene_map_id.

  For each flow containing interaction nodes, sets the flow's scene_map_id
  to the first interaction node's map_id (if not already set).

  Usage:
    mix migrate_interaction_to_scene          # execute migration
    mix migrate_interaction_to_scene --dry-run # preview changes only
  """

  use Mix.Task

  import Ecto.Query

  alias Storyarn.Flows
  alias Storyarn.Flows.{Flow, FlowNode}
  alias Storyarn.Repo

  @shortdoc "Migrate interaction node map_id to flow scene_map_id"

  @impl Mix.Task
  def run(args) do
    dry_run? = "--dry-run" in args

    Mix.Task.run("app.start")

    # Query all non-deleted interaction nodes with their flow info
    interaction_nodes =
      from(n in FlowNode,
        join: f in Flow,
        on: n.flow_id == f.id,
        where: n.type == "interaction" and is_nil(n.deleted_at) and is_nil(f.deleted_at),
        select: %{
          node_id: n.id,
          flow_id: f.id,
          flow_name: f.name,
          scene_map_id: f.scene_map_id,
          map_id: fragment("?->>'map_id'", n.data)
        },
        order_by: [asc: f.id, asc: n.inserted_at]
      )
      |> Repo.all()

    # Group by flow — take first node's map_id per flow
    by_flow = Enum.group_by(interaction_nodes, & &1.flow_id)

    Mix.shell().info(
      "Found #{length(interaction_nodes)} interaction nodes across #{map_size(by_flow)} flows."
    )

    if dry_run? do
      dry_run_report(by_flow)
    else
      execute_migration(by_flow)
    end
  end

  defp dry_run_report(by_flow) do
    Mix.shell().info("\n[DRY RUN] No changes will be made.\n")

    {would_migrate, already_set, no_map} =
      Enum.reduce(by_flow, {0, 0, 0}, fn {_flow_id, nodes}, {m, a, n} ->
        first = hd(nodes)

        cond do
          first.scene_map_id != nil ->
            Mix.shell().info(
              "  Skipped flow #{first.flow_id} \"#{first.flow_name}\": scene_map_id already set"
            )

            {m, a + 1, n}

          is_nil(first.map_id) or first.map_id == "" ->
            Mix.shell().info(
              "  Skipped flow #{first.flow_id}, node #{first.node_id}: map_id is nil"
            )

            {m, a, n + 1}

          true ->
            Mix.shell().info(
              "  Would set scene_map_id=#{first.map_id} on flow #{first.flow_id} " <>
                "\"#{first.flow_name}\" (from interaction node #{first.node_id})"
            )

            {m + 1, a, n}
        end
      end)

    Mix.shell().info(
      "\nSummary: #{would_migrate} would migrate, #{already_set} already set, #{no_map} skipped (no map)"
    )
  end

  defp execute_migration(by_flow) do
    {migrated, skipped_set, skipped_no_map, errors} =
      Enum.reduce(by_flow, {0, 0, 0, 0}, fn {_flow_id, nodes}, {m, s, n, e} ->
        first = hd(nodes)

        cond do
          first.scene_map_id != nil ->
            {m, s + 1, n, e}

          is_nil(first.map_id) or first.map_id == "" ->
            {m, s, n + 1, e}

          true ->
            do_migrate_flow(first, {m, s, n, e})
        end
      end)

    Mix.shell().info(
      "\nMigrated #{migrated} flows. Skipped: #{skipped_set} already set, #{skipped_no_map} no map. Errors: #{errors}."
    )
  end

  defp do_migrate_flow(first, {m, s, n, e}) do
    map_id = safe_to_integer(first.map_id)

    if is_nil(map_id) do
      Mix.shell().error("  Could not parse map_id \"#{first.map_id}\" for flow #{first.flow_id}")
      {m, s, n, e + 1}
    else
      case update_flow_scene_map(first.flow_id, map_id) do
        {:ok, _} ->
          Mix.shell().info(
            "  Set scene_map_id=#{map_id} on flow #{first.flow_id} \"#{first.flow_name}\""
          )

          {m + 1, s, n, e}

        {:error, reason} ->
          Mix.shell().error("  Failed to update flow #{first.flow_id}: #{inspect(reason)}")
          {m, s, n, e + 1}
      end
    end
  end

  defp update_flow_scene_map(flow_id, map_id) do
    case Repo.get(Flow, flow_id) do
      nil ->
        {:error, :flow_not_found}

      flow ->
        Flows.update_flow_scene(flow, %{"scene_map_id" => map_id})
    end
  end

  defp safe_to_integer(value) when is_integer(value), do: value

  defp safe_to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp safe_to_integer(_), do: nil
end
