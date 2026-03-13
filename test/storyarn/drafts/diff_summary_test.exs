defmodule Storyarn.Drafts.DiffSummaryTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Drafts
  alias Storyarn.Flows

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  defp setup_project(_context \\ %{}) do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  describe "build_merge_summary/1" do
    test "returns summary for flow draft" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project)

      {:ok, draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)

      # Add a node to the draft
      draft_entity = Drafts.get_draft_entity(draft)

      {:ok, _node} =
        Flows.create_node(draft_entity, %{
          "type" => "dialogue",
          "position_x" => 100,
          "position_y" => 100
        })

      assert {:ok, summary} = Drafts.build_merge_summary(draft)
      assert is_binary(summary.draft_changes)
      assert is_integer(summary.original_versions_since_fork)
      assert summary.original_versions_since_fork == 0
    end

    test "returns summary for sheet draft" do
      %{user: user, project: project} = setup_project()
      sheet = sheet_fixture(project)

      {:ok, draft} = Drafts.create_draft(project.id, "sheet", sheet.id, user.id)
      assert {:ok, summary} = Drafts.build_merge_summary(draft)
      assert is_binary(summary.draft_changes)
    end

    test "returns error for non-active draft" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project)

      {:ok, draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)
      {:ok, discarded} = Drafts.discard_draft(draft)

      assert {:error, :not_active} = Drafts.build_merge_summary(discarded)
    end

    test "detects original divergence" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project)

      # Backdate the draft so the version created below is clearly "after fork"
      {:ok, draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)

      backdated_at =
        draft.inserted_at
        |> DateTime.add(-60, :second)

      draft
      |> Ecto.Changeset.change(%{inserted_at: backdated_at})
      |> Storyarn.Repo.update!()

      draft = %{draft | inserted_at: backdated_at}

      # Create a version on the original after the (backdated) draft creation
      Storyarn.Versioning.create_version("flow", flow, project.id, user.id,
        title: "After fork change"
      )

      assert {:ok, summary} = Drafts.build_merge_summary(draft)
      assert summary.original_versions_since_fork == 1
    end
  end
end
