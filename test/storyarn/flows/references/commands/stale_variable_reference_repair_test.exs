defmodule Storyarn.Flows.StaleVariableReferenceRepairTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows
  alias Storyarn.Projects

  @invalid_project_ids [nil, "1", 0, -1, 9_223_372_036_854_775_808]

  test "rejects invalid PostgreSQL bigint identities without reaching Ecto" do
    for project_id <- @invalid_project_ids do
      assert {:error, :not_found} = Flows.repair_stale_variable_references(project_id)
      assert {:error, :not_found} = Projects.repair_stale_project_variable_references(project_id)
    end
  end
end
