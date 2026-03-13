defmodule Storyarn.Drafts.DraftLifecycleTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query, warn: false
  alias Storyarn.Drafts

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  defp setup_project(_context \\ %{}) do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  # ===========================================================================
  # rename_draft/2
  # ===========================================================================

  describe "rename_draft/2" do
    test "renames an active draft" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project)
      {:ok, draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)

      assert {:ok, updated} = Drafts.rename_draft(draft, "New Name")
      assert updated.name == "New Name"
    end

    test "validates name length" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project)
      {:ok, draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)

      assert {:error, changeset} = Drafts.rename_draft(draft, "")
      assert errors_on(changeset).name != []

      long_name = String.duplicate("a", 201)
      assert {:error, changeset} = Drafts.rename_draft(draft, long_name)
      assert errors_on(changeset).name != []
    end
  end

  # ===========================================================================
  # touch_draft/1
  # ===========================================================================

  describe "touch_draft/1" do
    test "returns error for non-existent draft" do
      assert {:error, :not_found} = Drafts.touch_draft(-1)
    end

    test "returns error for discarded draft" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project)
      {:ok, draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)
      {:ok, _} = Drafts.discard_draft(draft)

      assert {:error, :not_found} = Drafts.touch_draft(draft.id)
    end

    test "updates last_edited_at on an active draft" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project)
      {:ok, draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)

      # Backdate last_edited_at to ensure touch produces a newer timestamp
      past = DateTime.add(DateTime.utc_now(), -3600, :second) |> DateTime.truncate(:second)

      Storyarn.Repo.update_all(
        from(d in Storyarn.Drafts.Draft, where: d.id == ^draft.id),
        set: [last_edited_at: past]
      )

      assert :ok = Drafts.touch_draft(draft.id)

      updated = Storyarn.Repo.get!(Storyarn.Drafts.Draft, draft.id)
      assert DateTime.compare(updated.last_edited_at, past) == :gt
    end
  end

  # ===========================================================================
  # last_edited_at on create
  # ===========================================================================

  describe "create_draft sets last_edited_at" do
    test "last_edited_at is set on creation" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project)

      {:ok, draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)
      assert draft.last_edited_at != nil
    end
  end

  # ===========================================================================
  # list_my_drafts/2 with source names
  # ===========================================================================

  describe "list_my_drafts/2 with source names" do
    test "enriches drafts with source entity names" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project, %{name: "Test Flow"})
      {:ok, _draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)

      drafts = Drafts.list_my_drafts(project.id, user.id)
      assert [draft] = drafts
      assert draft.source_name == "Test Flow"
    end

    test "returns nil source_name for deleted source entities" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project, %{name: "Will Delete"})
      {:ok, _draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)

      # Hard-delete the source flow to simulate it being gone
      Storyarn.Repo.delete!(flow)

      drafts = Drafts.list_my_drafts(project.id, user.id)
      assert [draft] = drafts
      assert draft.source_name == nil
    end

    test "orders by last_edited_at descending" do
      %{user: user, project: project} = setup_project()
      flow1 = flow_fixture(project, %{name: "Flow A"})
      flow2 = flow_fixture(project, %{name: "Flow B"})

      {:ok, draft1} = Drafts.create_draft(project.id, "flow", flow1.id, user.id)
      {:ok, _draft2} = Drafts.create_draft(project.id, "flow", flow2.id, user.id)

      # Manually set draft1's last_edited_at to the future to ensure ordering
      future = DateTime.add(DateTime.utc_now(), 3600, :second) |> DateTime.truncate(:second)

      Storyarn.Repo.update_all(
        from(d in Storyarn.Drafts.Draft, where: d.id == ^draft1.id),
        set: [last_edited_at: future]
      )

      drafts = Drafts.list_my_drafts(project.id, user.id)
      assert [first | _] = drafts
      assert first.id == draft1.id
    end

    test "enriches drafts across different entity types" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project, %{name: "My Flow"})
      sheet = sheet_fixture(project, %{name: "My Sheet"})

      {:ok, _} = Drafts.create_draft(project.id, "flow", flow.id, user.id)
      {:ok, _} = Drafts.create_draft(project.id, "sheet", sheet.id, user.id)

      drafts = Drafts.list_my_drafts(project.id, user.id)
      assert length(drafts) == 2

      source_names = Enum.map(drafts, & &1.source_name) |> Enum.sort()
      assert source_names == ["My Flow", "My Sheet"]
    end
  end

  # ===========================================================================
  # rename_changeset
  # ===========================================================================

  describe "Draft.rename_changeset/2" do
    test "valid rename" do
      draft = %Storyarn.Drafts.Draft{name: "Old Name"}
      changeset = Storyarn.Drafts.Draft.rename_changeset(draft, %{name: "New Name"})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :name) == "New Name"
    end

    test "rejects empty name" do
      draft = %Storyarn.Drafts.Draft{name: "Old Name"}
      changeset = Storyarn.Drafts.Draft.rename_changeset(draft, %{name: ""})
      refute changeset.valid?
    end
  end
end
