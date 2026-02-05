defmodule Storyarn.Repo.Migrations.MigrateConditionNodesToCases do
  @moduledoc """
  Migrates existing condition nodes from binary (true/false) outputs
  to the new multi-output cases format.

  Old format: %{"expression" => "..."}
  New format: %{"expression" => "...", "cases" => [...]}
  """
  use Ecto.Migration

  import Ecto.Query

  def up do
    # Find all condition nodes that don't have a "cases" key in their data
    query =
      from(n in "flow_nodes",
        where: n.type == "condition",
        select: {n.id, n.data}
      )

    # Fetch and update each node
    for {id, data} <- repo().all(query) do
      # Skip if already has cases
      unless Map.has_key?(data, "cases") do
        updated_data =
          Map.put(data, "cases", [
            %{"id" => "case_true", "value" => "true", "label" => "True"},
            %{"id" => "case_false", "value" => "false", "label" => "False"}
          ])

        repo().update_all(
          from(n in "flow_nodes", where: n.id == ^id),
          set: [data: updated_data]
        )
      end
    end
  end

  def down do
    # Remove the "cases" key from condition nodes (revert to old format)
    query =
      from(n in "flow_nodes",
        where: n.type == "condition",
        select: {n.id, n.data}
      )

    for {id, data} <- repo().all(query) do
      if Map.has_key?(data, "cases") do
        updated_data = Map.delete(data, "cases")

        repo().update_all(
          from(n in "flow_nodes", where: n.id == ^id),
          set: [data: updated_data]
        )
      end
    end
  end
end
