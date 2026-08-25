defmodule Storyarn.Architecture.WorkspaceProjectLifecycleBoundaryTest do
  use ExUnit.Case, async: true

  alias Storyarn.Architecture.DependencyPolicy

  @workspace_delete "lib/storyarn/workspaces/lifecycle/commands/delete_workspace.ex"

  test "Workspace hard-delete consumes one Projects root-facade contract" do
    source = File.read!(@workspace_delete)

    assert source =~ "alias Storyarn.Projects"
    assert source =~ "Projects.prepare_workspace_data_hard_delete"
    assert source =~ "Projects.publish_committed_workspace_data_hard_delete"
    refute source =~ "Storyarn.Projects.Assets"
    refute source =~ "Storyarn.Projects.Versioning"
    refute source =~ "Assets.prepare_parent_hard_delete_locked"
    refute source =~ "Versioning.prepare_workspace"
  end

  test "the dependency ratchet records the root facade as durable and no Project internal as debt" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    assert Enum.any?(policy.durable_contracts, fn contract ->
             contract.source == @workspace_delete and
               contract.target == "lib/storyarn/projects.ex" and
               contract.kinds == ["runtime"]
           end)

    refute Enum.any?(policy.migration_exceptions, fn exception ->
             exception.source == @workspace_delete and
               String.starts_with?(exception.target, "lib/storyarn/projects/")
           end)
  end
end
