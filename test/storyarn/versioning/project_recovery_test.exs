defmodule Storyarn.Versioning.ProjectRecoveryTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Assets
  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.VariableReference
  alias Storyarn.Localization
  alias Storyarn.Localization.RuntimeKey
  alias Storyarn.Projects.Project
  alias Storyarn.ProjectTemplates.Audit
  alias Storyarn.Repo
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.EntityReference
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Versioning.Builders.ProjectSnapshotBuilder
  alias Storyarn.Versioning.ProjectRecovery
  alias Storyarn.Workspaces

  setup do
    user = user_fixture()
    project = project_fixture(user)
    workspace_id = project.workspace_id

    %{user: user, project: project, workspace_id: workspace_id}
  end

  describe "recover_project/4" do
    test "requires external transactions to provide a storage tracker", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, {:error, :asset_copy_tracker_required_in_transaction}} =
               Repo.transaction(fn ->
                 ProjectRecovery.recover_project(workspace_id, snapshot_data, user.id)
               end)
    end

    test "creates a new project from snapshot data", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      sheet_fixture(project, %{name: "Hero Sheet"})
      flow_fixture(project, %{name: "Main Flow"})
      scene_fixture(project, %{name: "World Map"})

      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, recovered} =
               ProjectRecovery.recover_project(workspace_id, snapshot_data, user.id, name: "My RPG (Recovered)")

      assert recovered.name == "My RPG (Recovered)"
      assert recovered.workspace_id == workspace_id
      assert recovered.id != project.id
    end

    test "revalidates workspace manager authorization inside the recovery transaction", %{
      project: project,
      user: owner
    } do
      workspace = workspace_fixture(owner)
      former_admin = user_fixture()
      membership = workspace_membership_fixture(workspace, former_admin, "admin")
      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)
      project_count = Repo.aggregate(Project, :count)

      assert {:ok, _membership} = Workspaces.remove_member(membership)

      assert {:error, :unauthorized} =
               ProjectRecovery.recover_project(
                 workspace.id,
                 snapshot_data,
                 former_admin.id
               )

      assert Repo.aggregate(Project, :count) == project_count
    end

    test "rechecks workspace capacity inside the recovery transaction", %{
      project: project,
      user: user
    } do
      workspace = workspace_fixture(user)
      _second = project_fixture(user, %{workspace: workspace})
      _third = project_fixture(user, %{workspace: workspace})
      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)
      project_count = Repo.aggregate(Project, :count)

      assert {:error, {:limit_reached, %{resource: :projects_per_workspace, used: 3, limit: 3}}} =
               ProjectRecovery.recover_project(
                 workspace.id,
                 snapshot_data,
                 user.id
               )

      assert Repo.aggregate(Project, :count) == project_count
    end

    test "repairs missing response identities while preserving valid response ids",
         %{project: project, workspace_id: workspace_id, user: user} do
      flow = flow_fixture(project, %{name: "Identity source"})

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Choose",
            "responses" => [
              %{"id" => "response_recovery_one", "text" => "One"},
              %{"id" => "response_recovery_two", "text" => "Two"}
            ]
          }
        })

      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      legacy_snapshot =
        update_in(snapshot_data, ["flows"], fn flows ->
          Enum.map(flows, fn
            %{"id" => flow_id, "snapshot" => flow_snapshot} = entry when flow_id == flow.id ->
              invalid_flow_snapshot =
                update_in(flow_snapshot, ["nodes"], fn nodes ->
                  Enum.map(nodes, fn
                    %{"original_id" => node_id, "data" => data} = node
                    when node_id == dialogue.id ->
                      responses = List.update_at(data["responses"], 1, &Map.delete(&1, "id"))

                      put_in(node, ["data", "responses"], responses)

                    node ->
                      node
                  end)
                end)

              Map.put(entry, "snapshot", invalid_flow_snapshot)

            entry ->
              entry
          end)
        end)

      assert {:ok, recovered} =
               ProjectRecovery.recover_project(
                 workspace_id,
                 legacy_snapshot,
                 user.id,
                 name: "Legacy response repair"
               )

      [recovered_flow] = Storyarn.Flows.list_flows(recovered.id)
      recovered_flow = Repo.preload(recovered_flow, :nodes)
      recovered_dialogue = Enum.find(recovered_flow.nodes, &(&1.type == "dialogue"))

      assert [
               %{"id" => "response_recovery_one"},
               %{"id" => repaired_response_id}
             ] = recovered_dialogue.data["responses"]

      assert RuntimeKey.valid_response_id?(repaired_response_id)
      assert repaired_response_id =~ "response_legacy_"
    end

    test "entity counts match original", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      sheet = sheet_fixture(project, %{name: "Hero Sheet"})
      block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}})

      flow = flow_fixture(project, %{name: "Main Flow"})
      node_fixture(flow, %{type: "dialogue"})
      scene_fixture(project, %{name: "World Map"})

      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      {:ok, recovered} =
        ProjectRecovery.recover_project(workspace_id, snapshot_data, user.id)

      new_sheets = Storyarn.Sheets.list_all_sheets(recovered.id)
      new_flows = Storyarn.Flows.list_flows(recovered.id)
      new_scenes = Storyarn.Scenes.list_scenes(recovered.id)

      assert length(new_sheets) == 1
      assert length(new_flows) == 1
      assert length(new_scenes) == 1
    end

    test "entities have new IDs", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      sheet = sheet_fixture(project, %{name: "Hero Sheet"})
      flow = flow_fixture(project, %{name: "Main Flow"})
      scene = scene_fixture(project, %{name: "World Map"})

      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      {:ok, recovered} =
        ProjectRecovery.recover_project(workspace_id, snapshot_data, user.id)

      [new_sheet] = Storyarn.Sheets.list_all_sheets(recovered.id)
      [new_flow] = Storyarn.Flows.list_flows(recovered.id)
      [new_scene] = Storyarn.Scenes.list_scenes(recovered.id)

      assert new_sheet.id != sheet.id
      assert new_flow.id != flow.id
      assert new_scene.id != scene.id

      assert new_sheet.name == "Hero Sheet"
      assert new_flow.name == "Main Flow"
      assert new_scene.name == "World Map"
    end

    test "creates owner membership for recovering user", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      {:ok, recovered} =
        ProjectRecovery.recover_project(workspace_id, snapshot_data, user.id)

      membership = Storyarn.Projects.get_membership(recovered.id, user.id)
      assert membership
      assert membership.role == "owner"
    end

    test "recovers empty project", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, recovered} =
               ProjectRecovery.recover_project(workspace_id, snapshot_data, user.id)

      assert Storyarn.Sheets.list_all_sheets(recovered.id) == []
      assert Storyarn.Flows.list_flows(recovered.id) == []
      assert Storyarn.Scenes.list_scenes(recovered.id) == []
    end

    test "preserves target localization configured before a source language", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      _spanish = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      _sheet = sheet_fixture(project, %{name: "Localized Sheet"})
      :ok = Localization.sync_sheet_names(project.id)

      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, recovered} =
               ProjectRecovery.recover_project(workspace_id, snapshot_data, user.id)

      assert [%{locale_code: "es", is_source: false}] =
               Localization.list_languages(recovered.id)

      assert [_localized_sheet_name] =
               Localization.list_texts_for_export(recovered.id, ["es"])
    end

    test "rejects a global localization row that disagrees with its entity snapshot", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      {_sheet, block} = localized_block_fixture(project)
      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)
      project_count_before = workspace_project_count(workspace_id)
      key = {"block", block.id, "value.content", "es"}

      malformed_snapshot =
        update_in(snapshot_data, ["localization", "texts"], fn texts ->
          Enum.map(texts, fn text ->
            if localization_snapshot_key(text) == key do
              text
              |> Map.put("source_text", "Tampered source")
              |> Map.put("source_text_hash", sha256("Tampered source"))
            else
              text
            end
          end)
        end)

      assert {:error, {:project_snapshot_runtime_localization_row_mismatch, ^key}} =
               ProjectRecovery.recover_project(
                 workspace_id,
                 malformed_snapshot,
                 user.id
               )

      assert workspace_project_count(workspace_id) == project_count_before
    end

    test "rejects a global localization catalog truncated consistently with its declared count", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      {_sheet, block} = localized_block_fixture(project)
      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)
      project_count_before = workspace_project_count(workspace_id)
      key = {"block", block.id, "value.content", "es"}

      malformed_snapshot =
        snapshot_data
        |> update_in(["localization", "texts"], fn texts ->
          Enum.reject(texts, &(localization_snapshot_key(&1) == key))
        end)
        |> update_in(["entity_counts", "localized_texts"], &(&1 - 1))

      assert {:error, {:project_snapshot_runtime_localization_coverage_mismatch, %{missing: [^key], unexpected: []}}} =
               ProjectRecovery.recover_project(
                 workspace_id,
                 malformed_snapshot,
                 user.id
               )

      assert workspace_project_count(workspace_id) == project_count_before
    end

    test "preserves archived orphan localization in the snapshot and defers its materialization", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      {_sheet, block} = localized_block_fixture(project)
      assert [text] = Localization.get_texts_for_source("block", block.id)

      assert {:ok, _text} =
               Localization.update_text(text, %{
                 translated_text: "Biografía archivada",
                 status: "final"
               })

      assert {:ok, _deleted_block} = Storyarn.Sheets.delete_block(block)

      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      archived_row =
        Enum.find(
          snapshot_data["localization"]["texts"],
          &(localization_snapshot_key(&1) == {"block", block.id, "value.content", "es"})
        )

      assert archived_row["archived_at"]
      assert archived_row["archive_reason"] == "source_deleted"

      assert {:ok, recovered} =
               ProjectRecovery.recover_project(
                 workspace_id,
                 snapshot_data,
                 user.id
               )

      recovered_texts = Localization.list_texts_for_backup(recovered.id, ["es"])

      refute Enum.any?(
               recovered_texts,
               &(&1.source_type == "block" and &1.source_id == block.id)
             )

      assert length(recovered_texts) ==
               snapshot_data["entity_counts"]["localized_texts"] - 1
    end

    test "restores tree hierarchy", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      parent = sheet_fixture(project, %{name: "Parent Sheet"})
      child = sheet_fixture(project, %{name: "Child Sheet"})

      # Move child under parent
      {:ok, _} = Storyarn.Sheets.move_sheet(child, parent.id, 0)

      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      {:ok, recovered} =
        ProjectRecovery.recover_project(workspace_id, snapshot_data, user.id)

      new_sheets = Storyarn.Sheets.list_all_sheets(recovered.id)
      new_parent = Enum.find(new_sheets, &(&1.name == "Parent Sheet"))
      new_child = Enum.find(new_sheets, &(&1.name == "Child Sheet"))

      assert new_child.parent_id == new_parent.id
    end

    test "uses default name when not provided", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      {:ok, recovered} =
        ProjectRecovery.recover_project(workspace_id, snapshot_data, user.id)

      assert recovered.name == "Recovered Project"
    end

    test "remaps cross-entity references across recovered flows and scenes", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      speaker =
        sheet_fixture(project, %{
          name: "Speaker Sheet",
          shortcut: "actors.speaker"
        })

      health =
        block_fixture(speaker, %{
          type: "number",
          variable_name: "health",
          config: %{"label" => "Health", "placeholder" => "0"}
        })

      scene = scene_fixture(project, %{name: "World Map"})
      target_scene = scene_fixture(project, %{name: "Dungeon Map"})
      flow = flow_fixture(project, %{name: "Main Flow"})
      subflow = flow_fixture(project, %{name: "Sub Flow"})

      {:ok, flow} = Storyarn.Flows.update_flow(flow, %{scene_id: scene.id})

      avatar_asset =
        uploaded_asset(
          project,
          user,
          "recovered-speaker-avatar.png",
          "recovered speaker avatar",
          "image/png"
        )

      {:ok, source_avatar} =
        Storyarn.Sheets.add_avatar(speaker, avatar_asset.id)

      _dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => speaker.id,
            "location_sheet_id" => speaker.id,
            "avatar_id" => source_avatar.id,
            "text" => "Hello"
          }
        })

      _subflow_node =
        node_fixture(flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => subflow.id}
        })

      _instruction =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "recover_health",
                "sheet" => speaker.shortcut,
                "variable" => health.variable_name,
                "operator" => "set",
                "value" => "100",
                "value_type" => "literal"
              }
            ]
          }
        })

      _pin =
        pin_fixture(scene, %{
          "label" => "Gate",
          "sheet_id" => speaker.id,
          "flow_id" => flow.id
        })

      _zone =
        zone_fixture(scene, %{
          "name" => "Portal",
          "target_type" => "scene",
          "target_id" => target_scene.id
        })

      _flow_zone =
        zone_fixture(scene, %{
          "name" => "Flow Portal",
          "target_type" => "flow",
          "target_id" => subflow.id
        })

      collection_item_id = Ecto.UUID.generate()

      _collection_zone =
        zone_fixture(scene, %{
          "name" => "Party Roster",
          "action_type" => "collection",
          "action_data" => %{
            "items" => [
              %{
                "id" => collection_item_id,
                "label" => "Speaker",
                "sheet_id" => speaker.id
              }
            ]
          }
        })

      {:ok, _ambient_flow} =
        Storyarn.Scenes.create_ambient_flow(scene.id, %{
          "flow_id" => subflow.id,
          "trigger_type" => "timed",
          "trigger_config" => %{"interval_ms" => 3_000},
          "priority" => 4,
          "enabled" => false,
          "position" => 2
        })

      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      {:ok, recovered} =
        ProjectRecovery.recover_project(workspace_id, snapshot_data, user.id)

      recovered_sheets = Storyarn.Sheets.list_all_sheets(recovered.id)
      recovered_flows = Storyarn.Flows.list_flows(recovered.id)
      recovered_scenes = Storyarn.Scenes.list_scenes(recovered.id)

      recovered_speaker = Enum.find(recovered_sheets, &(&1.name == "Speaker Sheet"))
      recovered_flow = Enum.find(recovered_flows, &(&1.name == "Main Flow"))
      recovered_subflow = Enum.find(recovered_flows, &(&1.name == "Sub Flow"))
      recovered_scene = Enum.find(recovered_scenes, &(&1.name == "World Map"))
      recovered_target_scene = Enum.find(recovered_scenes, &(&1.name == "Dungeon Map"))

      recovered_flow = Repo.preload(recovered_flow, :nodes, force: true)
      recovered_scene = Repo.preload(recovered_scene, [:pins, :zones], force: true)

      recovered_dialogue = Enum.find(recovered_flow.nodes, &(&1.type == "dialogue"))
      recovered_subflow_node = Enum.find(recovered_flow.nodes, &(&1.type == "subflow"))
      recovered_instruction = Enum.find(recovered_flow.nodes, &(&1.type == "instruction"))
      recovered_pin = Enum.find(recovered_scene.pins, &(&1.label == "Gate"))
      recovered_zone = Enum.find(recovered_scene.zones, &(&1.name == "Portal"))
      recovered_flow_zone = Enum.find(recovered_scene.zones, &(&1.name == "Flow Portal"))

      recovered_collection_zone =
        Enum.find(recovered_scene.zones, &(&1.name == "Party Roster"))

      recovered_health =
        recovered_speaker.id
        |> Storyarn.Sheets.list_blocks()
        |> Enum.find(&(&1.variable_name == "health"))

      [recovered_avatar] =
        Storyarn.Sheets.list_avatars(recovered_speaker.id)

      [recovered_ambient_flow] = Storyarn.Scenes.list_ambient_flows(recovered_scene.id)

      assert recovered_flow.scene_id == recovered_scene.id
      assert recovered_pin.sheet_id == recovered_speaker.id
      assert recovered_pin.flow_id == recovered_flow.id
      assert recovered_zone.target_type == "scene"
      assert recovered_zone.target_id == recovered_target_scene.id
      assert recovered_flow_zone.target_type == "flow"
      assert recovered_flow_zone.target_id == recovered_subflow.id

      assert [
               %{
                 "id" => ^collection_item_id,
                 "sheet_id" => recovered_collection_sheet_id
               }
             ] = recovered_collection_zone.action_data["items"]

      assert recovered_collection_sheet_id == recovered_speaker.id
      refute recovered_collection_sheet_id == speaker.id
      assert recovered_dialogue.data["speaker_sheet_id"] == recovered_speaker.id
      assert recovered_dialogue.data["location_sheet_id"] == recovered_speaker.id
      assert recovered_dialogue.data["avatar_id"] == recovered_avatar.id
      refute recovered_dialogue.data["avatar_id"] == source_avatar.id
      assert recovered_subflow_node.data["referenced_flow_id"] == recovered_subflow.id
      assert recovered_ambient_flow.flow_id == recovered_subflow.id
      assert recovered_ambient_flow.trigger_type == "timed"
      assert recovered_ambient_flow.trigger_config == %{"interval_ms" => 3_000}
      assert recovered_ambient_flow.priority == 4
      refute recovered_ambient_flow.enabled
      assert recovered_ambient_flow.position == 2

      assert Repo.exists?(
               from(reference in VariableReference,
                 where:
                   reference.source_type == "flow_node" and
                     reference.source_id == ^recovered_instruction.id and
                     reference.block_id == ^recovered_health.id and
                     reference.kind == "write"
               )
             )

      refute Repo.exists?(
               from(reference in EntityReference,
                 where:
                   (reference.source_type == "flow_node" and
                      reference.source_id == ^recovered_dialogue.id and
                      reference.target_id == ^speaker.id) or
                     (reference.source_type == "scene_pin" and
                        reference.source_id == ^recovered_pin.id and
                        reference.target_id in ^[speaker.id, flow.id]) or
                     (reference.source_type == "scene_zone" and
                        reference.source_id == ^recovered_zone.id and
                        reference.target_id == ^target_scene.id)
               )
             )

      assert Repo.exists?(
               from(reference in EntityReference,
                 where:
                   reference.source_type == "flow_node" and
                     reference.source_id == ^recovered_dialogue.id and
                     reference.target_type == "sheet" and
                     reference.target_id == ^recovered_speaker.id
               )
             )

      assert Repo.exists?(
               from(reference in EntityReference,
                 where:
                   reference.source_type == "scene_pin" and
                     reference.source_id == ^recovered_pin.id and
                     ((reference.target_type == "sheet" and
                         reference.target_id == ^recovered_speaker.id) or
                        (reference.target_type == "flow" and
                           reference.target_id == ^recovered_flow.id))
               )
             )

      assert Repo.exists?(
               from(reference in EntityReference,
                 where:
                   reference.source_type == "scene_zone" and
                     reference.source_id == ^recovered_zone.id and
                     reference.target_type == "scene" and
                     reference.target_id == ^recovered_target_scene.id
               )
             )

      assert Repo.exists?(
               from(reference in EntityReference,
                 where:
                   reference.source_type == "scene_zone" and
                     reference.source_id == ^recovered_collection_zone.id and
                     reference.target_type == "sheet" and
                     reference.target_id == ^recovered_speaker.id
               )
             )
    end

    test "rolls back recovery when a snapshot pairs an avatar with the wrong speaker", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      avatar_owner =
        sheet_fixture(project, %{name: "Avatar owner"})

      other_speaker =
        sheet_fixture(project, %{name: "Other speaker"})

      avatar_asset =
        uploaded_asset(
          project,
          user,
          "tampered-recovery-avatar.png",
          "tampered recovery avatar",
          "image/png"
        )

      {:ok, avatar} =
        Storyarn.Sheets.add_avatar(
          avatar_owner,
          avatar_asset.id
        )

      flow = flow_fixture(project, %{name: "Tampered flow"})

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => avatar_owner.id,
            "avatar_id" => avatar.id,
            "text" => "Tampered pairing"
          }
        })

      snapshot_data =
        ProjectSnapshotBuilder.build_snapshot(project.id)

      tampered_snapshot =
        Map.update!(snapshot_data, "flows", fn entries ->
          Enum.map(entries, fn
            %{"id" => flow_id, "snapshot" => flow_snapshot} = entry
            when flow_id == flow.id ->
              tampered_flow_snapshot =
                Map.update!(
                  flow_snapshot,
                  "nodes",
                  fn nodes ->
                    Enum.map(nodes, fn
                      %{"original_id" => node_id} = node
                      when node_id == dialogue.id ->
                        put_in(
                          node,
                          ["data", "speaker_sheet_id"],
                          other_speaker.id
                        )

                      node ->
                        node
                    end)
                  end
                )

              Map.put(
                entry,
                "snapshot",
                tampered_flow_snapshot
              )

            entry ->
              entry
          end)
        end)

      project_count_before =
        Repo.aggregate(
          from(candidate in Project,
            where: candidate.workspace_id == ^workspace_id
          ),
          :count
        )

      asset_count_before = Repo.aggregate(Asset, :count)

      assert {:error,
              {:materialization_failed, :flow, flow_id,
               {:avatar_speaker_mismatch, avatar_id, avatar_sheet_id, requested_speaker_id}}} =
               ProjectRecovery.recover_project(
                 workspace_id,
                 tampered_snapshot,
                 user.id,
                 name: "Rejected tampered recovery",
                 template_clone: true
               )

      assert flow_id == flow.id
      assert is_integer(avatar_id)
      assert is_integer(avatar_sheet_id)
      assert is_integer(requested_speaker_id)
      refute avatar_sheet_id == requested_speaker_id

      assert Repo.aggregate(
               from(candidate in Project,
                 where: candidate.workspace_id == ^workspace_id
               ),
               :count
             ) == project_count_before

      assert Repo.aggregate(Asset, :count) ==
               asset_count_before
    end

    test "remaps subflow exit pins to the recovered referenced flow exits", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      referenced_flow = flow_fixture(project, %{name: "Referenced Flow"})

      referenced_exit =
        node_fixture(referenced_flow, %{
          type: "exit",
          position_x: 300.0,
          data: %{
            "label" => "Referenced branch",
            "technical_id" => "referenced_branch",
            "exit_mode" => "terminal"
          }
        })

      caller_flow = flow_fixture(project, %{name: "Caller Flow"})

      subflow =
        node_fixture(caller_flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => referenced_flow.id}
        })

      caller_exit =
        caller_flow.id
        |> Storyarn.Flows.list_nodes()
        |> Enum.find(&(&1.type == "exit"))

      connection =
        Storyarn.FlowsFixtures.connection_fixture(caller_flow, subflow, caller_exit, %{
          source_pin: "exit_#{referenced_exit.id}"
        })

      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, recovered} =
               ProjectRecovery.recover_project(workspace_id, snapshot_data, user.id)

      recovered_flows = Storyarn.Flows.list_flows(recovered.id)
      recovered_referenced_flow = Enum.find(recovered_flows, &(&1.name == "Referenced Flow"))
      recovered_caller_flow = Enum.find(recovered_flows, &(&1.name == "Caller Flow"))

      recovered_referenced_exit =
        recovered_referenced_flow.id
        |> Storyarn.Flows.list_nodes()
        |> Enum.find(&((&1.data || %{})["technical_id"] == "referenced_branch"))

      recovered_subflow =
        recovered_caller_flow.id
        |> Storyarn.Flows.list_nodes()
        |> Enum.find(&(&1.type == "subflow"))

      recovered_connection =
        recovered_caller_flow.id
        |> Storyarn.Flows.list_connections()
        |> Enum.find(&(&1.source_node_id == recovered_subflow.id))

      assert recovered_subflow.data["referenced_flow_id"] == recovered_referenced_flow.id
      assert recovered_connection.source_pin == "exit_#{recovered_referenced_exit.id}"
      refute recovered_connection.source_pin == connection.source_pin
    end

    test "remaps embedded block, mention, terminal, and localization references", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      source_language_fixture(project, %{locale_code: "en", name: "English"})
      language_fixture(project, %{locale_code: "es", name: "Spanish"})

      source_sheet = sheet_fixture(project, %{name: "Reference Source"})
      target_sheet = sheet_fixture(project, %{name: "Reference Target"})
      target_flow = flow_fixture(project, %{name: "Referenced Flow"})
      target_scene = scene_fixture(project, %{name: "Referenced Scene"})

      reference_block =
        block_fixture(source_sheet, %{
          type: "reference",
          value: %{
            "target_type" => "flow",
            "target_id" => target_flow.id
          }
        })

      rich_text =
        ~s(<p><span class="mention" data-type="sheet" data-id="#{target_sheet.id}">Target</span></p>)

      rich_text_block =
        block_fixture(source_sheet, %{
          type: "rich_text",
          value: %{"content" => rich_text}
        })

      caller_flow = flow_fixture(project, %{name: "Caller Flow"})

      dialogue =
        node_fixture(caller_flow, %{
          type: "dialogue",
          data: %{
            "text" => rich_text,
            "speaker_sheet_id" => target_sheet.id
          }
        })

      exit =
        node_fixture(caller_flow, %{
          type: "exit",
          data: %{
            "label" => "Leave",
            "technical_id" => "leave",
            "exit_mode" => "terminal",
            "target_type" => "scene",
            "target_id" => target_scene.id
          }
        })

      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, recovered} =
               ProjectRecovery.recover_project(
                 workspace_id,
                 snapshot_data,
                 user.id
               )

      recovered_sheets = Storyarn.Sheets.list_all_sheets(recovered.id)
      recovered_target_sheet = Enum.find(recovered_sheets, &(&1.name == "Reference Target"))
      recovered_source_sheet = Enum.find(recovered_sheets, &(&1.name == "Reference Source"))

      recovered_flows = Storyarn.Flows.list_flows(recovered.id)
      recovered_target_flow = Enum.find(recovered_flows, &(&1.name == "Referenced Flow"))
      recovered_caller_flow = Enum.find(recovered_flows, &(&1.name == "Caller Flow"))
      recovered_target_scene = Enum.find(Storyarn.Scenes.list_scenes(recovered.id), &(&1.name == "Referenced Scene"))

      recovered_blocks = Storyarn.Sheets.list_blocks(recovered_source_sheet.id)
      recovered_reference = Enum.find(recovered_blocks, &(&1.type == "reference"))
      recovered_rich_text = Enum.find(recovered_blocks, &(&1.type == "rich_text"))

      recovered_nodes = Storyarn.Flows.list_nodes(recovered_caller_flow.id)
      recovered_dialogue = Enum.find(recovered_nodes, &(&1.type == "dialogue"))
      recovered_exit = Enum.find(recovered_nodes, &((&1.data || %{})["technical_id"] == "leave"))

      assert recovered_reference.value["target_type"] == "flow"
      assert recovered_reference.value["target_id"] == recovered_target_flow.id
      refute recovered_reference.value["target_id"] == target_flow.id

      assert recovered_rich_text.value["content"] =~
               ~s(data-id="#{recovered_target_sheet.id}")

      refute recovered_rich_text.value["content"] =~
               ~s(data-id="#{target_sheet.id}")

      assert recovered_dialogue.data["text"] =~
               ~s(data-id="#{recovered_target_sheet.id}")

      assert recovered_exit.data["target_type"] == "scene"
      assert recovered_exit.data["target_id"] == recovered_target_scene.id
      refute recovered_exit.data["target_id"] == target_scene.id

      assert Repo.exists?(
               from(reference in EntityReference,
                 where:
                   reference.source_type == "block" and
                     reference.source_id == ^recovered_reference.id and
                     reference.target_type == "flow" and
                     reference.target_id == ^recovered_target_flow.id
               )
             )

      assert Repo.exists?(
               from(reference in EntityReference,
                 where:
                   reference.source_type == "block" and
                     reference.source_id == ^recovered_rich_text.id and
                     reference.target_type == "sheet" and
                     reference.target_id == ^recovered_target_sheet.id
               )
             )

      assert Repo.exists?(
               from(reference in EntityReference,
                 where:
                   reference.source_type == "flow_node" and
                     reference.source_id == ^recovered_dialogue.id and
                     reference.target_type == "sheet" and
                     reference.target_id == ^recovered_target_sheet.id
               )
             )

      recovered_dialogue_text =
        recovered.id
        |> Localization.list_texts_for_export(["es"])
        |> Enum.find(
          &(&1.source_type == "flow_node" and
              &1.source_id == recovered_dialogue.id and
              &1.source_field == "text")
        )

      assert recovered_dialogue_text.source_text =~
               ~s(data-id="#{recovered_target_sheet.id}")

      assert recovered_dialogue_text.source_text_hash ==
               sha256(recovered_dialogue_text.source_text)

      refute recovered_dialogue_text.source_id == dialogue.id
      refute recovered_reference.id == reference_block.id
      refute recovered_rich_text.id == rich_text_block.id
      refute recovered_exit.id == exit.id
    end

    test "rolls back when a top-level entry ID disagrees with its snapshot root", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      sheet = sheet_fixture(project, %{name: "Identity"})
      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)
      project_count_before = workspace_project_count(workspace_id)

      malformed_snapshot =
        put_in(
          snapshot_data,
          ["sheets", Access.at(0), "id"],
          sheet.id + 1_000_000
        )

      assert {:error,
              {:materialization_failed, :sheet, entry_id,
               {:project_snapshot_root_id_mismatch, reported_entry_id, snapshot_id}}} =
               ProjectRecovery.recover_project(
                 workspace_id,
                 malformed_snapshot,
                 user.id
               )

      assert reported_entry_id == entry_id
      assert snapshot_id == sheet.id
      assert workspace_project_count(workspace_id) == project_count_before
    end

    test "rejects a truncated snapshot even when its tree is truncated consistently", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      _sheet = sheet_fixture(project, %{name: "Must not disappear"})
      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)
      project_count_before = workspace_project_count(workspace_id)

      truncated_snapshot =
        snapshot_data
        |> Map.put("sheets", [])
        |> put_in(["tree", "sheets"], [])

      assert {:error, {:project_snapshot_entity_count_mismatch, "sheets", 1, 0}} =
               ProjectRecovery.recover_project(
                 workspace_id,
                 truncated_snapshot,
                 user.id
               )

      assert workspace_project_count(workspace_id) == project_count_before
    end

    test "rolls back when the project tree contains a cycle", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      first = sheet_fixture(project, %{name: "First"})
      second = sheet_fixture(project, %{name: "Second"})
      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)
      project_count_before = workspace_project_count(workspace_id)

      malformed_snapshot =
        update_in(snapshot_data, ["tree", "sheets"], fn entries ->
          Enum.map(entries, fn entry ->
            case entry["id"] do
              id when id == first.id -> Map.put(entry, "parent_id", second.id)
              id when id == second.id -> Map.put(entry, "parent_id", first.id)
            end
          end)
        end)

      assert {:error, {:project_snapshot_tree_cycle, :sheet, _id}} =
               ProjectRecovery.recover_project(
                 workspace_id,
                 malformed_snapshot,
                 user.id
               )

      assert workspace_project_count(workspace_id) == project_count_before
    end

    test "rolls back when remapped blocks form a cross-sheet inheritance cycle", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      first_sheet = sheet_fixture(project, %{name: "First Sheet"})
      second_sheet = sheet_fixture(project, %{name: "Second Sheet"})
      first_block = block_fixture(first_sheet, %{type: "text"})
      second_block = block_fixture(second_sheet, %{type: "text"})

      snapshot_data =
        project.id
        |> ProjectSnapshotBuilder.build_snapshot()
        |> update_in(["sheets"], fn sheet_entries ->
          Enum.map(sheet_entries, fn entry ->
            parent_id =
              case entry["id"] do
                id when id == first_sheet.id -> second_block.id
                id when id == second_sheet.id -> first_block.id
              end

            update_in(entry, ["snapshot", "blocks"], fn blocks ->
              Enum.map(
                blocks,
                &Map.put(&1, "inherited_from_block_id", parent_id)
              )
            end)
          end)
        end)

      project_count_before = workspace_project_count(workspace_id)

      assert {:error, {:project_snapshot_inheritance_cycle, block_id}} =
               ProjectRecovery.recover_project(
                 workspace_id,
                 snapshot_data,
                 user.id
               )

      assert is_integer(block_id)
      assert workspace_project_count(workspace_id) == project_count_before
    end

    test "rolls back when remapped flows form a circular reference", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      first_flow = flow_fixture(project, %{name: "First Flow"})
      second_flow = flow_fixture(project, %{name: "Second Flow"})

      _first_to_second =
        node_fixture(first_flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => second_flow.id}
        })

      second_to_first = node_fixture(second_flow, %{type: "subflow", data: %{}})

      snapshot_data =
        project.id
        |> ProjectSnapshotBuilder.build_snapshot()
        |> update_in(["flows"], fn flow_entries ->
          Enum.map(flow_entries, fn
            %{"id" => flow_id} = entry when flow_id == second_flow.id ->
              update_in(entry, ["snapshot", "nodes"], fn nodes ->
                Enum.map(nodes, fn
                  %{"original_id" => node_id, "data" => data} = node
                  when node_id == second_to_first.id ->
                    Map.put(node, "data", Map.put(data || %{}, "referenced_flow_id", first_flow.id))

                  node ->
                    node
                end)
              end)

            entry ->
              entry
          end)
        end)

      project_count_before = workspace_project_count(workspace_id)

      assert {:error, {:circular_flow_reference, flow_id, node_id, target_flow_id}} =
               ProjectRecovery.recover_project(
                 workspace_id,
                 snapshot_data,
                 user.id
               )

      assert is_integer(flow_id)
      assert is_integer(node_id)
      assert is_integer(target_flow_id)
      assert workspace_project_count(workspace_id) == project_count_before
    end

    test "rolls back project recovery when a subflow exit pin cannot be mapped", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      referenced_flow = flow_fixture(project, %{name: "Referenced Flow"})
      caller_flow = flow_fixture(project, %{name: "Caller Flow"})

      subflow =
        node_fixture(caller_flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => referenced_flow.id}
        })

      caller_exit =
        caller_flow.id
        |> Storyarn.Flows.list_nodes()
        |> Enum.find(&(&1.type == "exit"))

      referenced_exit =
        referenced_flow.id
        |> Storyarn.Flows.list_nodes()
        |> Enum.find(&(&1.type == "exit"))

      connection =
        Storyarn.FlowsFixtures.connection_fixture(caller_flow, subflow, caller_exit, %{
          source_pin: "exit_#{referenced_exit.id}"
        })

      snapshot_data =
        project.id
        |> ProjectSnapshotBuilder.build_snapshot()
        |> update_in(["flows"], fn flow_entries ->
          Enum.map(flow_entries, fn
            %{"id" => flow_id, "snapshot" => snapshot} = entry when flow_id == caller_flow.id ->
              connections =
                Enum.map(snapshot["connections"], fn
                  %{"original_id" => connection_id} = connection_snapshot
                  when connection_id == connection.id ->
                    Map.put(connection_snapshot, "source_pin", "exit_#{caller_exit.id}")

                  connection_snapshot ->
                    connection_snapshot
                end)

              put_in(entry, ["snapshot", "connections"], connections)

            entry ->
              entry
          end)
        end)

      project_count_before =
        Repo.aggregate(
          from(existing_project in Project, where: existing_project.workspace_id == ^workspace_id),
          :count,
          :id
        )

      assert {:error, {:dynamic_exit_pin_not_materializable, connection_id, source_pin, reason}} =
               ProjectRecovery.recover_project(workspace_id, snapshot_data, user.id)

      assert connection_id == connection.id
      assert source_pin == "exit_#{caller_exit.id}"
      assert reason == :exit_not_in_referenced_flow_snapshot

      assert Repo.aggregate(
               from(existing_project in Project, where: existing_project.workspace_id == ^workspace_id),
               :count,
               :id
             ) == project_count_before
    end

    test "remaps subflow exit pins when snapshot IDs use mixed integer and string encodings", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      caller_flow = flow_fixture(project, %{name: "Caller Flow"})
      referenced_flow = flow_fixture(project, %{name: "Referenced Flow"})

      referenced_exit =
        node_fixture(referenced_flow, %{
          type: "exit",
          data: %{"label" => "Returned", "exit_mode" => "caller_return"}
        })

      subflow_node =
        node_fixture(caller_flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => to_string(referenced_flow.id)}
        })

      next_node = node_fixture(caller_flow, %{type: "hub"})

      connection =
        Storyarn.FlowsFixtures.connection_fixture(caller_flow, subflow_node, next_node, %{
          source_pin: "exit_#{referenced_exit.id}"
        })

      snapshot_data =
        project.id
        |> ProjectSnapshotBuilder.build_snapshot()
        |> update_flow_snapshot(caller_flow.id, fn snapshot ->
          update_in(snapshot["connections"], fn connections ->
            Enum.map(connections, fn
              %{"original_id" => original_id} = entry when original_id == connection.id ->
                Map.put(entry, "original_id", to_string(original_id))

              entry ->
                entry
            end)
          end)
        end)
        |> update_flow_snapshot(referenced_flow.id, fn snapshot ->
          update_in(snapshot["nodes"], fn nodes ->
            Enum.map(nodes, fn
              %{"original_id" => original_id} = entry when original_id == referenced_exit.id ->
                Map.put(entry, "original_id", to_string(original_id))

              entry ->
                entry
            end)
          end)
        end)

      assert {:ok, recovered} =
               ProjectRecovery.recover_project(workspace_id, snapshot_data, user.id)

      recovered_flows = Storyarn.Flows.list_flows(recovered.id)

      recovered_caller =
        recovered_flows
        |> Enum.find(&(&1.name == "Caller Flow"))
        |> Repo.preload([:connections, :nodes], force: true)

      recovered_referenced =
        recovered_flows
        |> Enum.find(&(&1.name == "Referenced Flow"))
        |> Repo.preload(:nodes, force: true)

      recovered_exit =
        Enum.find(
          recovered_referenced.nodes,
          &(&1.type == "exit" and &1.data["label"] == "Returned")
        )

      recovered_subflow = Enum.find(recovered_caller.nodes, &(&1.type == "subflow"))
      recovered_connection = Enum.find(recovered_caller.connections, &(&1.source_node_id == recovered_subflow.id))

      assert recovered_connection.source_pin == "exit_#{recovered_exit.id}"
      assert {:ok, %{"status" => "passed"}} = Audit.run(recovered.id)
    end

    test "rolls back recovery when a subflow exit pin has no referenced exit node", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      caller_flow = flow_fixture(project, %{name: "Caller Flow"})
      referenced_flow = flow_fixture(project, %{name: "Referenced Flow"})

      referenced_exit =
        node_fixture(referenced_flow, %{
          type: "exit",
          data: %{"label" => "Returned", "exit_mode" => "caller_return"}
        })

      subflow_node =
        node_fixture(caller_flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => referenced_flow.id}
        })

      next_node = node_fixture(caller_flow, %{type: "hub"})

      connection =
        Storyarn.FlowsFixtures.connection_fixture(caller_flow, subflow_node, next_node, %{
          source_pin: "exit_#{referenced_exit.id}"
        })

      snapshot_data =
        project.id
        |> ProjectSnapshotBuilder.build_snapshot()
        |> update_flow_snapshot(referenced_flow.id, fn snapshot ->
          update_in(snapshot["nodes"], fn nodes ->
            Enum.reject(nodes, &(&1["original_id"] == referenced_exit.id))
          end)
        end)

      assert {:error, {:dynamic_exit_pin_not_materializable, connection_id, source_pin, reason}} =
               ProjectRecovery.recover_project(workspace_id, snapshot_data, user.id)

      assert connection_id == connection.id
      assert source_pin == "exit_#{referenced_exit.id}"
      assert reason == :exit_not_in_referenced_flow_snapshot

      refute Repo.exists?(
               from project in Project,
                 where: project.workspace_id == ^workspace_id and project.name == "Recovered Project"
             )
    end

    test "normalizes legacy Hub colors while remapping recovered node data", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      speaker = sheet_fixture(project, %{name: "Hub Reference"})
      flow = flow_fixture(project, %{name: "Legacy Hub Flow"})

      hub =
        node_fixture(flow, %{
          type: "hub",
          data: %{
            "hub_id" => "checkpoint",
            "color" => "#3b82f6",
            "speaker_sheet_id" => speaker.id
          }
        })

      snapshot_data =
        project.id
        |> ProjectSnapshotBuilder.build_snapshot()
        |> update_in(["flows", Access.at(0), "snapshot", "nodes"], fn nodes ->
          Enum.map(nodes, fn
            %{"original_id" => original_id, "data" => data} = node when original_id == hub.id ->
              Map.put(node, "data", Map.put(data, "color", "blue"))

            node ->
              node
          end)
        end)

      assert {:ok, recovered} =
               ProjectRecovery.recover_project(workspace_id, snapshot_data, user.id)

      [recovered_speaker] = Storyarn.Sheets.list_all_sheets(recovered.id)

      recovered_hub =
        recovered.id
        |> Storyarn.Flows.list_flows()
        |> List.first()
        |> Repo.preload(:nodes)
        |> Map.fetch!(:nodes)
        |> Enum.find(&(&1.type == "hub"))

      assert recovered_hub.data["speaker_sheet_id"] == recovered_speaker.id
      assert recovered_hub.data["color"] == "#3b82f6"
    end

    test "remaps inherited blocks across recovered sheets", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      parent = sheet_fixture(project, %{name: "Parent Sheet"})

      source_block =
        block_fixture(parent, %{
          type: "text",
          position: 0,
          variable_name: "ancestor",
          config: %{"label" => "Ancestor"}
        })

      child = sheet_fixture(project, %{name: "Child Sheet"})

      inherited_block =
        block_fixture(child, %{
          type: "text",
          position: 0,
          variable_name: "descendant",
          config: %{"label" => "Descendant"}
        })

      Repo.update_all(from(b in Block, where: b.id == ^inherited_block.id),
        set: [inherited_from_block_id: source_block.id]
      )

      Repo.update_all(from(s in Sheet, where: s.id == ^child.id),
        set: [hidden_inherited_block_ids: [source_block.id]]
      )

      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      {:ok, recovered} =
        ProjectRecovery.recover_project(workspace_id, snapshot_data, user.id)

      recovered_sheets = Storyarn.Sheets.list_all_sheets(recovered.id)
      recovered_parent = Enum.find(recovered_sheets, &(&1.name == "Parent Sheet"))
      recovered_child = Enum.find(recovered_sheets, &(&1.name == "Child Sheet"))

      parent_blocks = Storyarn.Sheets.list_blocks(recovered_parent.id)
      child_blocks = Storyarn.Sheets.list_blocks(recovered_child.id)

      recovered_source_block = Enum.find(parent_blocks, &(&1.variable_name == "ancestor"))
      recovered_inherited_block = Enum.find(child_blocks, &(&1.variable_name == "descendant"))
      recovered_child = Repo.get!(Sheet, recovered_child.id)

      assert recovered_inherited_block.inherited_from_block_id == recovered_source_block.id
      assert recovered_child.hidden_inherited_block_ids == [recovered_source_block.id]
    end

    test "recovers a snapshot whose inherited source block is absent from the target DB", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      # Mirrors a portable-template import from another environment: the snapshot
      # references cross-sheet inheritance by ids that do not exist in the target
      # DB. Materialization must not violate blocks_inherited_from_block_id_fkey.
      parent = sheet_fixture(project, %{name: "Parent Sheet"})

      source_block =
        block_fixture(parent, %{type: "text", position: 0, variable_name: "ancestor"})

      child = sheet_fixture(project, %{name: "Child Sheet"})

      inherited_block =
        block_fixture(child, %{type: "text", position: 0, variable_name: "descendant"})

      Repo.update_all(from(b in Block, where: b.id == ^inherited_block.id),
        set: [inherited_from_block_id: source_block.id]
      )

      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      # Remove the original blocks so the snapshot's old ids exist nowhere in the
      # DB — exactly the state of a fresh import from an exported bundle.
      Repo.delete_all(from(b in Block, where: b.sheet_id in ^[parent.id, child.id]))

      {:ok, recovered} = ProjectRecovery.recover_project(workspace_id, snapshot_data, user.id)

      recovered_sheets = Storyarn.Sheets.list_all_sheets(recovered.id)
      recovered_parent = Enum.find(recovered_sheets, &(&1.name == "Parent Sheet"))
      recovered_child = Enum.find(recovered_sheets, &(&1.name == "Child Sheet"))

      recovered_source = Enum.find(Storyarn.Sheets.list_blocks(recovered_parent.id), &(&1.variable_name == "ancestor"))

      recovered_inherited =
        Enum.find(Storyarn.Sheets.list_blocks(recovered_child.id), &(&1.variable_name == "descendant"))

      assert recovered_inherited.inherited_from_block_id == recovered_source.id
    end

    test "template clone copies scene and flow assets into recovered project", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      background_asset = uploaded_asset(project, user, "map.png", "map-background", "image/png")
      pin_icon_asset = uploaded_asset(project, user, "pin.png", "pin-icon", "image/png")
      zone_icon_asset = uploaded_asset(project, user, "zone.png", "zone-icon", "image/png")
      audio_asset = uploaded_asset(project, user, "line.mp3", "audio-content", "audio/mpeg")

      scene = scene_fixture(project, %{name: "Asset Scene"})
      {:ok, scene} = Storyarn.Scenes.update_scene(scene, %{"background_asset_id" => background_asset.id})
      layer = layer_fixture(scene)

      _pin =
        pin_fixture(scene, %{
          "label" => "Asset Pin",
          "layer_id" => layer.id,
          "icon_asset_id" => pin_icon_asset.id
        })

      _zone =
        zone_fixture(scene, %{
          "name" => "Asset Zone",
          "layer_id" => layer.id,
          "label_mode" => "icon",
          "label_icon_asset_id" => zone_icon_asset.id
        })

      flow = flow_fixture(project, %{name: "Asset Flow"})

      _node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"speaker" => "Narrator", "text" => "Hello", "audio_asset_id" => audio_asset.id}
        })

      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, recovered} =
               ProjectRecovery.recover_project(workspace_id, snapshot_data, user.id,
                 name: "Template Copy",
                 template_clone: true
               )

      recovered_scene =
        recovered.id
        |> Storyarn.Scenes.list_scenes()
        |> Enum.find(&(&1.name == "Asset Scene"))
        |> Repo.preload(:background_asset)

      assert recovered_scene.background_asset.project_id == recovered.id
      refute recovered_scene.background_asset_id == background_asset.id
      on_exit(fn -> Assets.storage_delete(recovered_scene.background_asset.key) end)

      recovered_pin =
        recovered_scene.id
        |> Storyarn.Scenes.list_pins()
        |> Enum.find(&(&1.label == "Asset Pin"))
        |> Repo.preload(:icon_asset)

      assert recovered_pin.icon_asset.project_id == recovered.id
      refute recovered_pin.icon_asset_id == pin_icon_asset.id
      on_exit(fn -> Assets.storage_delete(recovered_pin.icon_asset.key) end)

      recovered_zone =
        recovered_scene.id
        |> Storyarn.Scenes.list_zones()
        |> Enum.find(&(&1.name == "Asset Zone"))

      assert recovered_zone.label_icon_asset.project_id == recovered.id
      refute recovered_zone.label_icon_asset_id == zone_icon_asset.id
      on_exit(fn -> Assets.storage_delete(recovered_zone.label_icon_asset.key) end)

      recovered_flow =
        recovered.id
        |> Storyarn.Flows.list_flows()
        |> Enum.find(&(&1.name == "Asset Flow"))
        |> Repo.preload(:nodes)

      recovered_audio_id =
        recovered_flow.nodes
        |> Enum.map(&(&1.data || %{})["audio_asset_id"])
        |> Enum.find(& &1)

      recovered_audio = Repo.get!(Asset, recovered_audio_id)
      assert recovered_audio.project_id == recovered.id
      refute recovered_audio.id == audio_asset.id
      on_exit(fn -> Assets.storage_delete(recovered_audio.key) end)
    end

    test "template clone preserves one copied asset identity across sheet banner, avatar, and gallery", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      shared_asset =
        uploaded_asset(
          project,
          user,
          "shared-sheet-#{System.unique_integer([:positive])}.png",
          "one source asset shared across every sheet surface",
          "image/png"
        )

      sheet = sheet_fixture(project, %{name: "Shared Asset Sheet"})
      assert {:ok, _sheet} = Storyarn.Sheets.update_sheet(sheet, %{banner_asset_id: shared_asset.id})
      assert {:ok, _avatar} = Storyarn.Sheets.add_avatar(sheet, shared_asset.id, %{name: "Shared avatar"})

      gallery_block =
        block_fixture(sheet, %{
          type: "gallery",
          config: %{"label" => "Shared gallery"},
          value: %{}
        })

      assert {:ok, _gallery_image} =
               Storyarn.Sheets.add_gallery_image(gallery_block, shared_asset.id)

      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, recovered} =
               ProjectRecovery.recover_project(
                 workspace_id,
                 snapshot_data,
                 user.id,
                 name: "Shared Sheet Asset Copy",
                 template_clone: true
               )

      recovered_sheet =
        recovered.id
        |> Storyarn.Sheets.list_all_sheets()
        |> Enum.find(&(&1.name == "Shared Asset Sheet"))
        |> then(&Repo.get!(Sheet, &1.id))

      [recovered_avatar] = Storyarn.Sheets.list_avatars(recovered_sheet.id)

      [recovered_gallery_block] =
        recovered_sheet.id
        |> Storyarn.Sheets.list_blocks()
        |> Enum.filter(&(&1.type == "gallery"))

      [recovered_gallery_image] =
        Storyarn.Sheets.list_gallery_images(recovered_gallery_block.id)

      assert [destination_asset_id] =
               Enum.uniq([
                 recovered_sheet.banner_asset_id,
                 recovered_avatar.asset_id,
                 recovered_gallery_image.asset_id
               ])

      refute destination_asset_id == shared_asset.id

      assert Repo.aggregate(
               from(asset in Asset,
                 where:
                   asset.project_id == ^recovered.id and
                     asset.blob_hash == ^shared_asset.blob_hash
               ),
               :count
             ) == 1

      destination_asset = Repo.get!(Asset, destination_asset_id)
      assert destination_asset.project_id == recovered.id
      assert {:ok, _binary} = Assets.storage_download(destination_asset.key)
      on_exit(fn -> Assets.storage_delete(destination_asset.key) end)
    end

    test "template clone copies localization voice assets into recovered project", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      source_language_fixture(project, %{locale_code: "en", name: "English"})
      language_fixture(project, %{locale_code: "es", name: "Spanish"})
      voice_asset = uploaded_asset(project, user, "localized-line.mp3", "voice-line", "audio/mpeg")

      flow = flow_fixture(project, %{name: "Localized Flow"})
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello"}})

      [text] = Localization.get_texts_for_source("flow_node", node.id)

      {:ok, _text} =
        Localization.update_text(text, %{
          translated_text: "Hola",
          vo_asset_id: voice_asset.id,
          vo_status: "recorded"
        })

      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, recovered} =
               ProjectRecovery.recover_project(workspace_id, snapshot_data, user.id,
                 name: "Template Copy",
                 template_clone: true
               )

      [recovered_text] = Localization.list_texts_for_export(recovered.id, ["es"])
      recovered_voice_asset = Repo.get!(Asset, recovered_text.vo_asset_id)

      assert recovered_text.content_role == "dialogue"
      assert recovered_text.vo_eligible
      assert recovered_voice_asset.project_id == recovered.id
      refute recovered_voice_asset.id == voice_asset.id
      assert {:ok, _binary} = Assets.storage_download(recovered_voice_asset.key)
      on_exit(fn -> Assets.storage_delete(recovered_voice_asset.key) end)
    end

    test "remaps response localization speakers into the recovered project", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      source_language_fixture(project, %{locale_code: "en", name: "English"})
      language_fixture(project, %{locale_code: "es", name: "Spanish"})
      speaker = sheet_fixture(project, %{name: "Response Speaker"})
      flow = flow_fixture(project, %{name: "Response Localization"})

      _node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => speaker.id,
            "text" => "Choose",
            "responses" => [%{"id" => "continue", "text" => "Continue"}]
          }
        })

      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, recovered} =
               ProjectRecovery.recover_project(
                 workspace_id,
                 snapshot_data,
                 user.id,
                 name: "Recovered response localization"
               )

      [recovered_speaker] =
        Enum.filter(
          Storyarn.Sheets.list_all_sheets(recovered.id),
          &(&1.name == "Response Speaker")
        )

      response_text =
        recovered.id
        |> Localization.list_texts_for_export(["es"])
        |> Enum.find(&(&1.source_field == "response.continue.text"))

      assert response_text.content_role == "response"
      assert response_text.speaker_sheet_id == recovered_speaker.id
      refute response_text.speaker_sheet_id == speaker.id
    end

    test "normal recovery preserves one asset identity across flow snapshots and global voice-over", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      {snapshot_data, source_asset} =
        shared_flow_and_voice_asset_snapshot(
          project,
          user,
          "normal-shared-#{System.unique_integer([:positive])}.mp3"
        )

      assert {:ok, recovered} =
               ProjectRecovery.recover_project(
                 workspace_id,
                 snapshot_data,
                 user.id,
                 name: "Shared asset recovery"
               )

      assert_recovered_shared_asset_identity(recovered, source_asset)
    end

    test "template clone preserves one copied asset identity across flow snapshots and global voice-over", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      {snapshot_data, source_asset} =
        shared_flow_and_voice_asset_snapshot(
          project,
          user,
          "template-shared-#{System.unique_integer([:positive])}.mp3"
        )

      assert {:ok, recovered} =
               ProjectRecovery.recover_project(
                 workspace_id,
                 snapshot_data,
                 user.id,
                 name: "Shared template asset",
                 template_clone: true
               )

      assert_recovered_shared_asset_identity(recovered, source_asset)
    end

    test "missing voice-over blob rolls back project, assets, and earlier storage copies", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      source_language_fixture(project, %{locale_code: "en", name: "English"})
      language_fixture(project, %{locale_code: "es", name: "Spanish"})

      suffix = System.unique_integer([:positive])

      good_asset =
        uploaded_asset(
          project,
          user,
          "rollback-good-#{suffix}.mp3",
          "good asset copied before global localization",
          "audio/mpeg"
        )

      missing_asset =
        uploaded_asset(
          project,
          user,
          "rollback-missing-#{suffix}.mp3",
          "voice asset whose canonical blob disappears",
          "audio/mpeg"
        )

      flow = flow_fixture(project, %{name: "Rollback Flow"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Rollback line",
            "audio_asset_id" => good_asset.id
          }
        })

      [text] = Localization.get_texts_for_source("flow_node", node.id)

      assert {:ok, _text} =
               Localization.update_text(text, %{
                 translated_text: "Línea de rollback",
                 vo_asset_id: missing_asset.id,
                 vo_status: "recorded"
               })

      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      missing_blob_key =
        BlobStore.blob_key(
          project.id,
          missing_asset.blob_hash,
          BlobStore.ext_from_content_type(missing_asset.content_type)
        )

      assert :ok = delete_storage_blob(missing_blob_key)

      project_count_before = workspace_project_count(workspace_id)
      asset_count_before = Repo.aggregate(Asset, :count)
      copied_paths_before = stored_asset_paths(good_asset.filename)

      assert {:error, {:asset_materialization_failed, missing_asset_id, {:asset_blob_unavailable, _reason}}} =
               ProjectRecovery.recover_project(
                 workspace_id,
                 snapshot_data,
                 user.id,
                 name: "Must roll back"
               )

      assert missing_asset_id == missing_asset.id
      assert workspace_project_count(workspace_id) == project_count_before
      assert Repo.aggregate(Asset, :count) == asset_count_before
      assert stored_asset_paths(good_asset.filename) == copied_paths_before
    end

    test "same-sized corrupted blob rolls back the recovered project without materializing false hash metadata", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      expected_content = "expected"
      corrupted_content = "tampered"

      asset =
        uploaded_asset(
          project,
          user,
          "corrupt-recovery-#{System.unique_integer([:positive])}.mp3",
          expected_content,
          "audio/mpeg"
        )

      flow = flow_fixture(project, %{name: "Corrupted Asset Recovery"})

      _node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "This asset must not be materialized",
            "audio_asset_id" => asset.id
          }
        })

      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      blob_key =
        BlobStore.blob_key(
          project.id,
          asset.blob_hash,
          BlobStore.ext_from_content_type(asset.content_type)
        )

      actual_hash = BlobStore.compute_hash(corrupted_content)

      assert byte_size(corrupted_content) == byte_size(expected_content)
      refute actual_hash == asset.blob_hash
      assert {:ok, _url} = Assets.storage_upload(blob_key, corrupted_content, asset.content_type)

      project_count_before = workspace_project_count(workspace_id)
      asset_count_before = Repo.aggregate(Asset, :count)
      copied_paths_before = stored_asset_paths(asset.filename)

      recovery_result =
        ProjectRecovery.recover_project(
          workspace_id,
          snapshot_data,
          user.id,
          name: "Must reject corrupted blob",
          template_clone: true
        )

      assert {:error, {:materialization_failed, :flow, flow_id, asset_error}} =
               recovery_result

      assert {:asset_materialization_failed, asset_id, checksum_error} = asset_error
      assert checksum_error == :blob_hash_mismatch

      assert flow_id == flow.id
      assert asset_id == asset.id
      assert workspace_project_count(workspace_id) == project_count_before
      assert Repo.aggregate(Asset, :count) == asset_count_before
      assert stored_asset_paths(asset.filename) == copied_paths_before
    end

    test "restores archived language state instead of making the locale active again", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      source_language_fixture(project, %{locale_code: "en", name: "English"})
      spanish = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      assert {:ok, archived_spanish} = Localization.remove_language(spanish)

      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, recovered} =
               ProjectRecovery.recover_project(workspace_id, snapshot_data, user.id, name: "Recovered archived locale")

      recovered_spanish =
        recovered.id
        |> Localization.list_languages_for_backup()
        |> Enum.find(&(&1.locale_code == "es"))

      assert recovered_spanish.archived_at == archived_spanish.archived_at
      refute Enum.any?(Localization.list_languages(recovered.id), &(&1.locale_code == "es"))
    end
  end

  defp uploaded_asset(project, user, filename, content, content_type) do
    {:ok, asset} =
      Assets.upload_binary_and_create_asset(
        content,
        %{filename: filename, content_type: content_type},
        project,
        user
      )

    on_exit(fn ->
      Assets.storage_delete(asset.key)

      delete_storage_blob(BlobStore.blob_key(project.id, asset.blob_hash, BlobStore.ext_from_content_type(content_type)))
    end)

    asset
  end

  defp shared_flow_and_voice_asset_snapshot(project, user, filename) do
    source_language_fixture(project, %{locale_code: "en", name: "English"})
    language_fixture(project, %{locale_code: "es", name: "Spanish"})

    source_asset =
      uploaded_asset(
        project,
        user,
        filename,
        "one source asset shared by two flows and global localization",
        "audio/mpeg"
      )

    first_flow = flow_fixture(project, %{name: "Shared Asset Flow A"})

    first_node =
      node_fixture(first_flow, %{
        type: "dialogue",
        data: %{
          "text" => "Shared line A",
          "audio_asset_id" => source_asset.id
        }
      })

    second_flow = flow_fixture(project, %{name: "Shared Asset Flow B"})

    _second_node =
      node_fixture(second_flow, %{
        type: "dialogue",
        data: %{
          "text" => "Shared line B",
          "audio_asset_id" => source_asset.id
        }
      })

    [first_text] =
      Localization.get_texts_for_source(
        "flow_node",
        first_node.id
      )

    assert {:ok, _text} =
             Localization.update_text(first_text, %{
               translated_text: "Línea compartida",
               vo_asset_id: source_asset.id,
               vo_status: "recorded"
             })

    {ProjectSnapshotBuilder.build_snapshot(project.id), source_asset}
  end

  defp assert_recovered_shared_asset_identity(recovered, source_asset) do
    recovered_audio_ids =
      from(node in FlowNode,
        join: flow in assoc(node, :flow),
        where:
          flow.project_id == ^recovered.id and
            node.type == "dialogue" and
            is_nil(node.deleted_at),
        select: node.data
      )
      |> Repo.all()
      |> Enum.map(& &1["audio_asset_id"])
      |> Enum.reject(&is_nil/1)

    assert length(recovered_audio_ids) == 2
    assert [destination_asset_id] = Enum.uniq(recovered_audio_ids)

    recovered_voice_text =
      recovered.id
      |> Localization.list_texts_for_export(["es"])
      |> Enum.find(&(&1.vo_asset_id == destination_asset_id))

    assert recovered_voice_text
    refute destination_asset_id == source_asset.id

    assert 1 ==
             Repo.aggregate(
               from(asset in Asset,
                 where:
                   asset.project_id == ^recovered.id and
                     asset.blob_hash == ^source_asset.blob_hash
               ),
               :count
             )

    destination_asset = Repo.get!(Asset, destination_asset_id)
    assert destination_asset.project_id == recovered.id
    assert {:ok, _binary} = Assets.storage_download(destination_asset.key)
    on_exit(fn -> Assets.storage_delete(destination_asset.key) end)
  end

  defp workspace_project_count(workspace_id) do
    Repo.aggregate(
      from(project in Project, where: project.workspace_id == ^workspace_id),
      :count
    )
  end

  defp localized_block_fixture(project) do
    source_language_fixture(project, %{locale_code: "en", name: "English"})
    language_fixture(project, %{locale_code: "es", name: "Spanish"})
    sheet = sheet_fixture(project, %{name: "Localized Sheet"})

    block =
      block_fixture(sheet, %{
        type: "rich_text",
        value: %{"content" => "A localizable biography"}
      })

    {sheet, block}
  end

  defp localization_snapshot_key(text) do
    {
      text["source_type"],
      text["source_id"],
      text["source_field"],
      text["locale_code"]
    }
  end

  defp sha256(value) do
    :sha256
    |> :crypto.hash(value)
    |> Base.encode16(case: :lower)
  end

  defp stored_asset_paths(filename) do
    upload_dir =
      :storyarn
      |> Application.fetch_env!(:storage)
      |> Keyword.fetch!(:upload_dir)
      |> Path.expand()

    upload_dir
    |> Path.join("projects/*/assets/*/#{filename}")
    |> Path.wildcard()
    |> MapSet.new()
  end

  defp update_flow_snapshot(snapshot_data, flow_id, update_fun) do
    update_in(snapshot_data["flows"], fn flows ->
      Enum.map(flows, fn
        %{"id" => ^flow_id, "snapshot" => snapshot} = entry ->
          Map.put(entry, "snapshot", update_fun.(snapshot))

        entry ->
          entry
      end)
    end)
  end
end
