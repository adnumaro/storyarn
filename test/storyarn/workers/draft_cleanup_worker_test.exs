defmodule Storyarn.Workers.DraftCleanupWorkerTest do
  use Storyarn.DataCase, async: true
  use Oban.Testing, repo: Storyarn.Repo

  import Ecto.Query, warn: false

  alias Storyarn.Drafts
  alias Storyarn.Workers.DraftCleanupWorker

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  defp setup_project(_context \\ %{}) do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  describe "perform/1" do
    test "cleans up orphaned entities from discarded drafts" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project)
      {:ok, draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)

      # Discard the draft (this should already clean up, but let's test the safety net)
      {:ok, discarded} = Drafts.discard_draft(draft)

      # Backdate the updated_at to simulate an old discarded draft
      Storyarn.Repo.update_all(
        from(d in Storyarn.Drafts.Draft, where: d.id == ^discarded.id),
        set: [updated_at: DateTime.add(DateTime.utc_now(), -172_800, :second)]
      )

      assert :ok = perform_job(DraftCleanupWorker, %{})
    end

    test "does not affect active drafts" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project)
      {:ok, draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)

      # Sanity: cloned entity exists
      assert Drafts.get_draft_entity(draft) != nil

      assert :ok = perform_job(DraftCleanupWorker, %{})

      # Draft should still be active and entity intact
      reloaded = Drafts.get_draft(draft.id)
      assert reloaded.status == "active"
      assert Drafts.get_draft_entity(reloaded) != nil
    end

    test "does not affect recently merged drafts" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project)
      {:ok, draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)

      # Merge the draft
      {:ok, _} = Drafts.merge_draft(draft, user.id)

      # Worker should skip recent merges (within 24h)
      assert :ok = perform_job(DraftCleanupWorker, %{})
    end
  end
end
