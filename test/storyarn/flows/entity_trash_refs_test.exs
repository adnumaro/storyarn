defmodule Storyarn.Flows.EntityTrashRefsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.EntityTrashRef
  alias Storyarn.Flows.EntityTrashRefs
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Repo
  alias Storyarn.Sheets

  defp make_node_with_speaker(flow, sheet_id) do
    node_fixture(flow, %{
      type: "dialogue",
      data: %{"text" => "hi", "speaker_sheet_id" => sheet_id}
    })
  end

  # ===========================================================================
  # sweep_jsonb_field
  # ===========================================================================

  describe "sweep_jsonb_field/6 (data.speaker_sheet_id)" do
    test "nullifies the jsonb key on each matching row and inserts trash refs" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)
      sheet = sheet_fixture(project)

      n1 = make_node_with_speaker(flow, sheet.id)
      n2 = make_node_with_speaker(flow, sheet.id)
      # Different sheet — should NOT be swept
      other_sheet = sheet_fixture(project)
      n_other = make_node_with_speaker(flow, other_sheet.id)

      assert {:ok, 2} =
               EntityTrashRefs.sweep_jsonb_field(
                 FlowNode,
                 "flow_node",
                 :data,
                 "speaker_sheet_id",
                 :sheet,
                 sheet.id
               )

      # Key preserved, value nil'd
      assert Repo.get!(FlowNode, n1.id).data["speaker_sheet_id"] == nil
      assert Map.has_key?(Repo.get!(FlowNode, n1.id).data, "speaker_sheet_id")
      assert Repo.get!(FlowNode, n2.id).data["speaker_sheet_id"] == nil
      # Untouched row
      assert Repo.get!(FlowNode, n_other.id).data["speaker_sheet_id"] == other_sheet.id

      refs = Repo.all(EntityTrashRef)
      assert length(refs) == 2

      assert Enum.all?(refs, fn r ->
               r.source_type == "flow_node" and
                 r.source_field == "data.speaker_sheet_id" and
                 r.target_sheet_id == sheet.id
             end)
    end

    test "no matches is a no-op" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      assert {:ok, 0} =
               EntityTrashRefs.sweep_jsonb_field(
                 FlowNode,
                 "flow_node",
                 :data,
                 "speaker_sheet_id",
                 :sheet,
                 sheet.id
               )

      assert Repo.aggregate(EntityTrashRef, :count) == 0
    end

    test "rejects unknown source_type" do
      assert_raise ArgumentError, fn ->
        EntityTrashRefs.sweep_jsonb_field(
          FlowNode,
          "not_a_source",
          :data,
          "speaker_sheet_id",
          :sheet,
          1
        )
      end
    end

    test "rejects unknown target_type" do
      assert_raise ArgumentError, fn ->
        EntityTrashRefs.sweep_jsonb_field(
          FlowNode,
          "flow_node",
          :data,
          "speaker_sheet_id",
          :not_a_target,
          1
        )
      end
    end
  end

  # ===========================================================================
  # restore
  # ===========================================================================

  describe "restore/2 after sweep_jsonb_field" do
    test "re-applies jsonb key if currently nil" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)
      sheet = sheet_fixture(project)
      n1 = make_node_with_speaker(flow, sheet.id)

      {:ok, 1} =
        EntityTrashRefs.sweep_jsonb_field(
          FlowNode,
          "flow_node",
          :data,
          "speaker_sheet_id",
          :sheet,
          sheet.id
        )

      assert {:ok, %{restored: 1, skipped: 0}} = EntityTrashRefs.restore(:sheet, sheet.id)
      assert Repo.get!(FlowNode, n1.id).data["speaker_sheet_id"] == sheet.id
    end

    test "skips if the user reassigned the jsonb key in the interim" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)
      sheet = sheet_fixture(project)
      other_sheet = sheet_fixture(project)
      n1 = make_node_with_speaker(flow, sheet.id)

      {:ok, 1} =
        EntityTrashRefs.sweep_jsonb_field(
          FlowNode,
          "flow_node",
          :data,
          "speaker_sheet_id",
          :sheet,
          sheet.id
        )

      # User re-points n1 to a different sheet
      node = Repo.get!(FlowNode, n1.id)
      new_data = Map.put(node.data, "speaker_sheet_id", other_sheet.id)
      node |> Ecto.Changeset.change(%{data: new_data}) |> Repo.update!()

      assert {:ok, %{restored: 0, skipped: 1}} = EntityTrashRefs.restore(:sheet, sheet.id)
      assert Repo.get!(FlowNode, n1.id).data["speaker_sheet_id"] == other_sheet.id
    end
  end

  describe "reconcile_project_restore_flow_refs/3" do
    test "does not re-fetch and mutate a foreign source inserted after source validation" do
      user = user_fixture()
      project = project_fixture(user)
      target_flow = flow_fixture(project)
      foreign_project = project_fixture(user)
      foreign_flow = flow_fixture(foreign_project)

      [[missing_source_id]] =
        Repo.query!("SELECT nextval(pg_get_serial_sequence('flow_nodes', 'id'))").rows

      pending_ref =
        %EntityTrashRef{}
        |> EntityTrashRef.create_changeset(%{
          source_type: "flow_node",
          source_id: missing_source_id,
          source_field: "data.referenced_flow_id",
          target_flow_id: target_flow.id
        })
        |> Repo.insert!()

      handler_id =
        "project-restore-missing-source-race-#{System.unique_integer([:positive])}"

      :ok =
        :telemetry.attach(
          handler_id,
          [
            :storyarn,
            :flows,
            :entity_trash_refs,
            :project_restore_sources_locked
          ],
          fn _event, _measurements, %{project_id: restored_project_id}, _config ->
            if restored_project_id == project.id do
              Repo.insert!(%FlowNode{
                id: missing_source_id,
                flow_id: foreign_flow.id,
                type: "subflow",
                data: %{"referenced_flow_id" => nil}
              })
            end
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert {:ok, %{discarded: 0, restored: 0, skipped: 1}} =
               EntityTrashRefs.reconcile_project_restore_flow_refs(
                 project.id,
                 [target_flow.id],
                 []
               )

      assert Repo.get!(FlowNode, missing_source_id).data["referenced_flow_id"] == nil
      refute Repo.get(EntityTrashRef, pending_ref.id)
    end
  end

  # ===========================================================================
  # FK cascade
  # ===========================================================================

  describe "FK cascade on target hard-delete" do
    test "hard-deleting a sheet drops trash refs pointing at it via target_sheet_id" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)
      sheet = sheet_fixture(project)
      _n1 = make_node_with_speaker(flow, sheet.id)

      {:ok, 1} =
        EntityTrashRefs.sweep_jsonb_field(
          FlowNode,
          "flow_node",
          :data,
          "speaker_sheet_id",
          :sheet,
          sheet.id
        )

      assert Repo.aggregate(EntityTrashRef, :count) == 1

      # Hard-delete (permanently_delete_sheet triggers the cascade)
      {:ok, _} = Sheets.permanently_delete_sheet(sheet)

      assert Repo.aggregate(EntityTrashRef, :count) == 0
    end
  end

  # ===========================================================================
  # Facade delegates
  # ===========================================================================

  describe "Flows facade delegates" do
    test "sweep_trash_refs_jsonb works through facade" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)
      sheet = sheet_fixture(project)
      _n1 = make_node_with_speaker(flow, sheet.id)

      assert {:ok, 1} =
               Flows.sweep_trash_refs_jsonb(
                 FlowNode,
                 "flow_node",
                 :data,
                 "speaker_sheet_id",
                 :sheet,
                 sheet.id
               )

      assert {:ok, %{restored: 1}} = Flows.restore_trash_refs(:sheet, sheet.id)
    end
  end
end
