defmodule Storyarn.Versioning.ProjectRecoveryTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Accounts.User
  alias Storyarn.Assets
  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.VariableReference
  alias Storyarn.Localization
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Localization.TextCrud
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.SceneAmbientFlow
  alias Storyarn.Scenes.SceneConnection
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.EntityReference
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Versioning.Builders.ProjectSnapshotBuilder
  alias Storyarn.Versioning.ProjectRecovery
  alias Storyarn.Versioning.SnapshotObjectFormat

  setup do
    user = user_fixture()
    project = project_fixture(user)
    workspace_id = project.workspace_id

    %{user: user, project: project, workspace_id: workspace_id}
  end

  describe "materialize_template/4" do
    test "requires external transactions to provide a storage tracker", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, {:error, :asset_copy_tracker_required_in_transaction}} =
               Repo.transaction(fn ->
                 ProjectRecovery.materialize_template(workspace_id, snapshot_data, user.id)
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
               ProjectRecovery.materialize_template(workspace_id, snapshot_data, user.id, name: "My RPG (Recovered)")

      assert recovered.name == "My RPG (Recovered)"
      assert recovered.workspace_id == workspace_id
      assert recovered.id != project.id
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
        ProjectRecovery.materialize_template(workspace_id, snapshot_data, user.id)

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
        ProjectRecovery.materialize_template(workspace_id, snapshot_data, user.id)

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
        ProjectRecovery.materialize_template(workspace_id, snapshot_data, user.id)

      membership = Storyarn.Projects.get_membership(recovered.id, user.id)
      assert membership
      assert membership.role == "owner"
    end

    test "discards localization actor identities when installing into another workspace", %{
      project: source_project,
      user: source_owner
    } do
      source_language_fixture(source_project, %{locale_code: "en", name: "English"})
      language_fixture(source_project, %{locale_code: "es", name: "Spanish"})
      reviewer = user_fixture()
      membership_fixture(source_project, reviewer, "editor")
      flow = flow_fixture(source_project, %{name: "Attributed localization"})
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello"}})
      [text] = Localization.get_texts_for_source("flow_node", node.id)

      assert {:ok, _text} =
               Localization.update_text(text, %{
                 translated_text: "Hola",
                 translated_by_id: source_owner.id,
                 reviewed_by_id: reviewer.id
               })

      snapshot_data = ProjectSnapshotBuilder.build_snapshot(source_project.id)
      target_owner = user_fixture()
      target_project = project_fixture(target_owner, %{name: "Target workspace project"})

      assert {:ok, recovered} =
               ProjectRecovery.materialize_template(
                 target_project.workspace_id,
                 snapshot_data,
                 target_owner.id
               )

      [restored_text] = Localization.list_texts_for_export(recovered.id, ["es"])
      assert restored_text.translated_by_id == nil
      assert restored_text.reviewed_by_id == nil
    end

    test "recovers empty project", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, recovered} =
               ProjectRecovery.materialize_template(workspace_id, snapshot_data, user.id)

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
               ProjectRecovery.materialize_template(workspace_id, snapshot_data, user.id)

      assert [%{locale_code: "es", is_source: false}] =
               Localization.list_languages(recovered.id)

      assert [_localized_sheet_name] =
               Localization.list_texts_for_export(recovered.id, ["es"])
    end

    test "canonicalizes missing runtime translations in global and nested snapshots and recovers them", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _ca = language_fixture(project, %{locale_code: "ca", name: "Catalan"})

      sheet = sheet_fixture(project, %{name: "Hero"})

      block =
        block_fixture(sheet, %{
          type: "text",
          variable_name: "biography",
          value: %{"content" => "Biography"}
        })

      flow = flow_fixture(project, %{name: "Introduction"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Welcome", "responses" => []}
        })

      assert {3, _rows} =
               Repo.delete_all(
                 from(text in LocalizedText,
                   where:
                     text.locale_code == "ca" and
                       ((text.source_type == "sheet" and text.source_id == ^sheet.id and
                           text.source_field == "name") or
                          (text.source_type == "block" and text.source_id == ^block.id and
                             text.source_field == "value.content") or
                          (text.source_type == "flow_node" and text.source_id == ^node.id and
                             text.source_field == "text"))
                 )
               )

      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      nested_rows =
        Enum.flat_map(snapshot_data["sheets"] ++ snapshot_data["flows"], &get_in(&1, ["snapshot", "localization"]))

      global_rows = snapshot_data["localization"]["texts"]

      expected_contracts = %{
        {"sheet", sheet.id, "name", "ca"} => {"speaker_name", false},
        {"block", block.id, "value.content", "ca"} => {"runtime_value", false},
        {"flow_node", node.id, "text", "ca"} => {"dialogue", true}
      }

      assert expected_contracts |> Map.keys() |> Enum.sort() ==
               global_rows |> Enum.map(&localization_snapshot_key/1) |> Enum.sort()

      for {key, {content_role, vo_eligible}} <- expected_contracts do
        global_row = Enum.find(global_rows, &(localization_snapshot_key(&1) == key))
        nested_row = Enum.find(nested_rows, &(localization_snapshot_key(&1) == key))

        assert Map.drop(global_row, ["content_role", "vo_eligible"]) == nested_row
        assert global_row["content_role"] == content_role
        assert global_row["vo_eligible"] == vo_eligible
        assert global_row["status"] == "pending"
        assert global_row["translated_text"] == nil
        assert global_row["translated_source_hash"] == nil
        assert global_row["vo_asset_id"] == nil
        assert global_row["translated_by_id"] == nil
        assert global_row["reviewed_by_id"] == nil
      end

      assert snapshot_data["entity_counts"]["localized_texts"] == 3
      assert [] = Localization.get_texts_for_source("sheet", sheet.id)
      assert [] = Localization.get_texts_for_source("block", block.id)
      assert [] = Localization.get_texts_for_source("flow_node", node.id)

      assert {:ok, recovered} =
               ProjectRecovery.materialize_template(
                 workspace_id,
                 snapshot_data,
                 user.id
               )

      restored_rows = Localization.list_texts_for_export(recovered.id, ["ca"])
      assert length(restored_rows) == 3

      assert Enum.all?(restored_rows, fn row ->
               row.status == "pending" and is_nil(row.translated_text) and
                 is_nil(row.translated_source_hash) and is_nil(row.vo_asset_id) and
                 is_nil(row.translated_by_id) and is_nil(row.reviewed_by_id)
             end)
    end

    test "replaces an archived runtime row with the canonical pending row in portable backups", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      {_sheet, block} = localized_block_fixture(project)

      assert {1, nil} =
               TextCrud.archive_texts_for_source(
                 "block",
                 block.id,
                 "source_deleted"
               )

      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)
      key = {"block", block.id, "value.content", "es"}

      assert [global_row] =
               Enum.filter(
                 snapshot_data["localization"]["texts"],
                 &(localization_snapshot_key(&1) == key)
               )

      nested_row =
        snapshot_data["sheets"]
        |> Enum.flat_map(&get_in(&1, ["snapshot", "localization"]))
        |> Enum.find(&(localization_snapshot_key(&1) == key))

      assert is_nil(global_row["archived_at"])
      assert global_row["status"] == "pending"
      assert Map.drop(global_row, ["content_role", "vo_eligible"]) == nested_row

      assert {:ok, _recovered} =
               ProjectRecovery.materialize_template(
                 workspace_id,
                 snapshot_data,
                 user.id
               )
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
               ProjectRecovery.materialize_template(
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
               ProjectRecovery.materialize_template(
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
               ProjectRecovery.materialize_template(
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
        ProjectRecovery.materialize_template(workspace_id, snapshot_data, user.id)

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
        ProjectRecovery.materialize_template(workspace_id, snapshot_data, user.id)

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
        ProjectRecovery.materialize_template(workspace_id, snapshot_data, user.id)

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
               ProjectRecovery.materialize_template(
                 workspace_id,
                 tampered_snapshot,
                 user.id,
                 name: "Rejected tampered recovery"
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
               ProjectRecovery.materialize_template(workspace_id, snapshot_data, user.id)

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
               ProjectRecovery.materialize_template(
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
               ProjectRecovery.materialize_template(
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
               ProjectRecovery.materialize_template(
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
               ProjectRecovery.materialize_template(
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
               ProjectRecovery.materialize_template(
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
               ProjectRecovery.materialize_template(
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
               ProjectRecovery.materialize_template(workspace_id, snapshot_data, user.id)

      assert connection_id == connection.id
      assert source_pin == "exit_#{caller_exit.id}"
      assert reason == :exit_not_in_referenced_flow_snapshot

      assert Repo.aggregate(
               from(existing_project in Project, where: existing_project.workspace_id == ^workspace_id),
               :count,
               :id
             ) == project_count_before
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
               ProjectRecovery.materialize_template(workspace_id, snapshot_data, user.id)

      assert connection_id == connection.id
      assert source_pin == "exit_#{referenced_exit.id}"
      assert reason == :exit_not_in_referenced_flow_snapshot

      refute Repo.exists?(
               from project in Project,
                 where: project.workspace_id == ^workspace_id and project.name == "Recovered Project"
             )
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
        ProjectRecovery.materialize_template(workspace_id, snapshot_data, user.id)

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

      {:ok, recovered} = ProjectRecovery.materialize_template(workspace_id, snapshot_data, user.id)

      recovered_sheets = Storyarn.Sheets.list_all_sheets(recovered.id)
      recovered_parent = Enum.find(recovered_sheets, &(&1.name == "Parent Sheet"))
      recovered_child = Enum.find(recovered_sheets, &(&1.name == "Child Sheet"))

      recovered_source = Enum.find(Storyarn.Sheets.list_blocks(recovered_parent.id), &(&1.variable_name == "ancestor"))

      recovered_inherited =
        Enum.find(Storyarn.Sheets.list_blocks(recovered_child.id), &(&1.variable_name == "descendant"))

      assert recovered_inherited.inherited_from_block_id == recovered_source.id
    end

    test "portable materialization copies scene and flow assets into the destination project", %{
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
               ProjectRecovery.materialize_template(workspace_id, snapshot_data, user.id, name: "Template Copy")

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

    test "portable materialization preserves one copied asset identity across sheet surfaces", %{
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
               ProjectRecovery.materialize_template(
                 workspace_id,
                 snapshot_data,
                 user.id,
                 name: "Shared Sheet Asset Copy"
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

    test "portable materialization copies localization voice assets into the destination project", %{
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
               ProjectRecovery.materialize_template(workspace_id, snapshot_data, user.id, name: "Template Copy")

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
               ProjectRecovery.materialize_template(
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

    test "portable materialization preserves one copied asset identity across flow and voice-over", %{
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
               ProjectRecovery.materialize_template(
                 workspace_id,
                 snapshot_data,
                 user.id,
                 name: "Shared template asset"
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
               ProjectRecovery.materialize_template(
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
        ProjectRecovery.materialize_template(
          workspace_id,
          snapshot_data,
          user.id,
          name: "Must reject corrupted blob"
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
               ProjectRecovery.materialize_template(workspace_id, snapshot_data, user.id,
                 name: "Recovered archived locale"
               )

      recovered_spanish =
        recovered.id
        |> Localization.list_languages_for_backup()
        |> Enum.find(&(&1.locale_code == "es"))

      assert recovered_spanish.archived_at == archived_spanish.archived_at
      refute Enum.any?(Localization.list_languages(recovered.id), &(&1.locale_code == "es"))
    end
  end

  describe "materialize_into_project/5" do
    test "requires the caller's final restore transaction", %{project: source_project, user: user} do
      snapshot_data = canonical_snapshot(source_project)
      target_project = project_fixture(user)

      assert {:error, :project_materialization_requires_transaction} =
               ProjectRecovery.materialize_into_project(
                 target_project,
                 snapshot_data,
                 user.id,
                 %{},
                 localization_scope: :active
               )
    end

    test "requires exact restore to declare the active localization scope", %{
      project: source_project,
      user: user
    } do
      snapshot_data = canonical_snapshot(source_project)
      target_project = project_fixture(user)

      assert {:error, :project_materialization_requires_active_localization} =
               ProjectRecovery.materialize_into_project(
                 target_project,
                 snapshot_data,
                 user.id,
                 %{}
               )

      assert {:error, :project_materialization_requires_active_localization} =
               ProjectRecovery.materialize_into_project(
                 target_project,
                 snapshot_data,
                 user.id,
                 %{},
                 localization_scope: :backup
               )
    end

    test "requires exact restore to provide the localization actor prelock result", %{
      project: source_project,
      user: user
    } do
      snapshot_data = canonical_snapshot(source_project)
      target_project = project_fixture(user)

      assert {:ok, {:error, :project_materialization_localization_actor_prelock_required}} =
               Repo.transaction(fn ->
                 locked_project =
                   Repo.one!(
                     from candidate in Project,
                       where: candidate.id == ^target_project.id,
                       lock: "FOR UPDATE"
                   )

                 ProjectRecovery.materialize_into_project(
                   locked_project,
                   snapshot_data,
                   user.id,
                   %{},
                   localization_scope: :active
                 )
               end)
    end

    test "rejects archived languages before writing into the existing project", %{
      project: source_project,
      user: user
    } do
      source_language_fixture(source_project, %{locale_code: "en", name: "English"})
      spanish = language_fixture(source_project, %{locale_code: "es", name: "Spanish"})
      assert {:ok, _archived} = Localization.remove_language(spanish)

      snapshot_data = canonical_snapshot(source_project)
      target_project = project_fixture(user)
      counts_before = materialized_graph_counts(target_project.id)

      assert {:error, :archived_project_snapshot_language_not_materializable} =
               ProjectRecovery.validate_materialization_snapshot(snapshot_data)

      assert {:error, :archived_project_snapshot_language_not_materializable} =
               materialize_snapshot_into_project(target_project, snapshot_data, user.id, %{})

      assert materialized_graph_counts(target_project.id) == counts_before
      assert Localization.list_languages_for_backup(target_project.id) == []
    end

    test "restores canonical glossary entries whose target language was removed", %{
      project: source_project,
      user: user
    } do
      source_language_fixture(source_project, %{locale_code: "en", name: "English"})
      spanish = language_fixture(source_project, %{locale_code: "es", name: "Spanish"})

      assert {:ok, glossary} =
               Localization.create_glossary_entry(source_project, %{
                 source_term: "Dragon",
                 source_locale: "en",
                 target_term: "Dragón",
                 target_locale: "es",
                 context: "Creature"
               })

      assert {:ok, _archived} = Localization.remove_language(spanish)

      snapshot_data = active_canonical_snapshot(source_project)
      assert Enum.map(snapshot_data["localization"]["languages"], & &1["locale_code"]) == ["en"]
      assert [%{"target_locale" => "es", "target_term" => "Dragón"}] = snapshot_data["localization"]["glossary"]
      assert :ok = ProjectRecovery.validate_materialization_snapshot(snapshot_data)

      target_project = project_fixture(user, %{name: "Glossary target"})

      assert {:ok, _materialized_project} =
               materialize_snapshot_into_project(
                 target_project,
                 snapshot_data,
                 user.id,
                 %{}
               )

      assert Enum.map(Localization.list_languages(target_project.id), & &1.locale_code) == ["en"]

      assert [restored_glossary] = Localization.list_glossary_for_export(target_project.id)
      assert restored_glossary.source_term == glossary.source_term
      assert restored_glossary.source_locale == "en"
      assert restored_glossary.target_term == "Dragón"
      assert restored_glossary.target_locale == "es"
    end

    test "exact materialization preserves an incomplete localization inventory without synthesizing rows", %{
      project: source_project,
      user: user
    } do
      {_sheet, block} = localized_block_fixture(source_project)
      key = {"block", block.id, "value.content", "es"}

      snapshot_data =
        source_project
        |> active_canonical_snapshot()
        |> update_in(["localization", "texts"], fn texts ->
          Enum.reject(texts, &(localization_snapshot_key(&1) == key))
        end)
        |> update_in(["entity_counts", "localized_texts"], &(&1 - 1))

      assert {:error, {:project_snapshot_runtime_localization_coverage_mismatch, _details}} =
               ProjectRecovery.validate_materialization_snapshot(snapshot_data)

      target_project = project_fixture(user, %{name: "Exact localization target"})

      assert {:ok, _materialized_project} =
               materialize_snapshot_into_project(
                 target_project,
                 snapshot_data,
                 user.id,
                 %{},
                 materialization_mode: :exact
               )

      restored_sheet =
        target_project.id
        |> Storyarn.Sheets.list_all_sheets()
        |> Enum.find(&(&1.name == "Localized Sheet"))

      [restored_block] = Storyarn.Sheets.list_blocks(restored_sheet.id)
      assert [] = Localization.get_texts_for_source("block", restored_block.id)
    end

    test "exact materialization preserves authored unresolved ids, mentions, nulls, and FK-safe archived references", %{
      project: source_project,
      user: user
    } do
      source_language_fixture(source_project, %{locale_code: "en", name: "English"})
      language_fixture(source_project, %{locale_code: "es", name: "Spanish"})

      target_project = project_fixture(user, %{name: "Exact authored references target"})
      target_archived_speaker = sheet_fixture(target_project, %{name: "Target archived speaker"})
      target_source_sheet = sheet_fixture(target_project, %{name: "Target archived inheritance source"})

      target_archived_block =
        block_fixture(target_source_sheet, %{type: "text", variable_name: "archived_target_source"})

      known_mention = sheet_fixture(source_project, %{name: "Known mention"})
      authored_sheet = sheet_fixture(source_project, %{name: "Authored unresolved state"})
      null_sheet = sheet_fixture(source_project, %{name: "Null hidden state"})

      dangling_id = 2_000_000_000 + rem(System.unique_integer([:positive]), 100_000_000)

      valid_rich_text =
        ~s(<p><span class="mention" data-type="sheet" data-id="#{known_mention.id}">Known</span></p>)

      rich_text =
        ~s(<p><span class="mention" data-type="sheet" data-id="#{known_mention.id}">Known</span><span class="mention" data-type="sheet" data-id="#{dangling_id}">Missing</span></p>)

      authored_block =
        block_fixture(authored_sheet, %{
          type: "rich_text",
          value: %{"content" => valid_rich_text},
          inherited_from_block_id: target_archived_block.id
        })

      [localized_text] = Localization.get_texts_for_source("block", authored_block.id)

      Repo.update_all(
        from(block in Block, where: block.id == ^authored_block.id),
        set: [value: %{"content" => rich_text}]
      )

      Repo.update_all(
        from(text in LocalizedText, where: text.id == ^localized_text.id),
        set: [
          source_text: rich_text,
          source_text_hash: sha256(rich_text),
          speaker_sheet_id: target_archived_speaker.id
        ]
      )

      now = DateTime.utc_now(:second)

      Repo.update_all(
        from(block in Block, where: block.id == ^target_archived_block.id),
        set: [deleted_at: now]
      )

      Repo.update_all(
        from(sheet in Sheet, where: sheet.id == ^target_archived_speaker.id),
        set: [deleted_at: now]
      )

      Repo.update_all(
        from(sheet in Sheet, where: sheet.id == ^authored_sheet.id),
        set: [hidden_inherited_block_ids: [target_archived_block.id, dangling_id]]
      )

      Repo.update_all(
        from(sheet in Sheet, where: sheet.id == ^null_sheet.id),
        set: [hidden_inherited_block_ids: nil]
      )

      snapshot_data = active_exact_capture_snapshot(source_project)

      Repo.update_all(
        from(text in LocalizedText,
          where: text.project_id == ^source_project.id and is_nil(text.archived_at)
        ),
        set: [archived_at: DateTime.utc_now(:second), archive_reason: "version_replaced"]
      )

      assert {:ok, _materialized_project} =
               materialize_snapshot_into_project(
                 target_project,
                 snapshot_data,
                 user.id,
                 %{},
                 materialization_mode: :exact
               )

      restored_sheets = Storyarn.Sheets.list_all_sheets(target_project.id)
      restored_known = Enum.find(restored_sheets, &(&1.name == "Known mention"))
      restored_authored = Enum.find(restored_sheets, &(&1.name == "Authored unresolved state"))
      restored_null = Enum.find(restored_sheets, &(&1.name == "Null hidden state"))
      [restored_block] = Storyarn.Sheets.list_blocks(restored_authored.id)

      restored_authored = Repo.get!(Sheet, restored_authored.id)
      restored_null = Repo.get!(Sheet, restored_null.id)

      assert restored_authored.hidden_inherited_block_ids == [target_archived_block.id, dangling_id]
      assert restored_null.hidden_inherited_block_ids == nil
      assert restored_block.inherited_from_block_id == target_archived_block.id
      assert restored_block.value["content"] =~ ~s(data-id="#{restored_known.id}")
      assert restored_block.value["content"] =~ ~s(data-id="#{dangling_id}")

      [restored_text] = Localization.get_texts_for_source("block", restored_block.id)
      assert restored_text.speaker_sheet_id == target_archived_speaker.id
      assert restored_text.source_text =~ ~s(data-id="#{restored_known.id}")
      assert restored_text.source_text =~ ~s(data-id="#{dangling_id}")
    end

    test "exact materialization preserves same-project archived FKs and remaps global scene pins", %{
      project: source_project,
      user: user
    } do
      source_sheet = sheet_fixture(source_project, %{name: "Captured pin sheet"})
      source_flow = flow_fixture(source_project, %{name: "Captured physical flow"})
      source_scene = scene_fixture(source_project, %{name: "Captured physical scene"})
      source_pin_scene = scene_fixture(source_project, %{name: "Captured pin owner"})

      source_pin =
        pin_fixture(source_pin_scene, %{
          "label" => "Cross-scene captured pin",
          "sheet_id" => source_sheet.id,
          "flow_id" => source_flow.id
        })

      source_connection =
        Repo.insert!(%SceneConnection{
          scene_id: source_scene.id,
          from_pin_id: source_pin.id,
          waypoints: []
        })

      raw_source_connection =
        Repo.insert!(%SceneConnection{
          scene_id: source_scene.id,
          to_pin_id: source_pin.id,
          waypoints: []
        })

      {:ok, _source_ambient} =
        Storyarn.Scenes.create_ambient_flow(source_scene.id, %{
          "flow_id" => source_flow.id,
          "trigger_type" => "timed",
          "trigger_config" => %{"interval_ms" => 2_000}
        })

      snapshot_data = active_exact_capture_snapshot(source_project)

      Repo.delete!(source_connection)
      Repo.delete!(raw_source_connection)
      Repo.delete!(source_pin)

      target_project = project_fixture(user, %{name: "Archived FK target"})
      archived_sheet = sheet_fixture(target_project, %{name: "Archived target sheet"})
      archived_flow = flow_fixture(target_project, %{name: "Archived target flow"})
      archived_scene = scene_fixture(target_project, %{name: "Archived target scene"})
      archived_pin = pin_fixture(archived_scene, %{"label" => "Archived target pin"})
      now = DateTime.utc_now(:second)

      Repo.update_all(from(sheet in Sheet, where: sheet.id == ^archived_sheet.id), set: [deleted_at: now])
      Repo.update_all(from(flow in Flow, where: flow.id == ^archived_flow.id), set: [deleted_at: now])
      Repo.update_all(from(scene in Scene, where: scene.id == ^archived_scene.id), set: [deleted_at: now])

      exact_snapshot =
        snapshot_data
        |> update_snapshot_entity("flows", source_flow.id, fn flow_snapshot ->
          Map.put(flow_snapshot, "scene_id", archived_scene.id)
        end)
        |> update_snapshot_entity("scenes", source_pin_scene.id, fn scene_snapshot ->
          update_scene_pin_snapshot(scene_snapshot, source_pin.id, fn pin ->
            pin
            |> Map.put("sheet_id", archived_sheet.id)
            |> Map.put("flow_id", archived_flow.id)
          end)
        end)
        |> update_snapshot_entity("scenes", source_scene.id, fn scene_snapshot ->
          scene_snapshot
          |> update_in(["ambient_flows"], fn ambient_flows ->
            Enum.map(ambient_flows, &Map.put(&1, "flow_id", archived_flow.id))
          end)
          |> update_in(["connections"], fn connections ->
            Enum.map(connections, fn
              %{"original_id" => id} = connection when id == raw_source_connection.id ->
                connection
                |> Map.put("to_layer_index", nil)
                |> Map.put("to_pin_index", nil)
                |> Map.put("to_pin_original_id", archived_pin.id)

              connection ->
                connection
            end)
          end)
        end)

      assert {:ok, _materialized_project} =
               materialize_snapshot_into_project(
                 target_project,
                 exact_snapshot,
                 user.id,
                 %{},
                 materialization_mode: :exact
               )

      restored_flow = Enum.find(Storyarn.Flows.list_flows(target_project.id), &(&1.name == source_flow.name))
      restored_scene = Enum.find(Storyarn.Scenes.list_scenes(target_project.id), &(&1.name == source_scene.name))

      restored_pin_scene =
        Enum.find(Storyarn.Scenes.list_scenes(target_project.id), &(&1.name == source_pin_scene.name))

      restored_pin = Repo.one!(from(pin in ScenePin, where: pin.scene_id == ^restored_pin_scene.id))

      restored_connections =
        Repo.all(from(connection in SceneConnection, where: connection.scene_id == ^restored_scene.id))

      restored_connection = Enum.find(restored_connections, &(&1.from_pin_id == restored_pin.id))
      restored_raw_connection = Enum.find(restored_connections, &(&1.to_pin_id == archived_pin.id))

      restored_ambient = Repo.one!(from(ambient in SceneAmbientFlow, where: ambient.scene_id == ^restored_scene.id))

      assert restored_flow.scene_id == archived_scene.id
      assert restored_pin.sheet_id == archived_sheet.id
      assert restored_pin.flow_id == archived_flow.id
      assert restored_connection.from_pin_id == restored_pin.id
      refute restored_connection.from_pin_id == source_pin.id
      assert restored_raw_connection.to_pin_id == archived_pin.id
      assert restored_ambient.flow_id == archived_flow.id
    end

    test "exact materialization rejects every cross-project physical FK with rollback", %{
      project: source_project,
      user: user
    } do
      source_sheet = sheet_fixture(source_project)
      source_flow = flow_fixture(source_project)
      source_scene = scene_fixture(source_project)
      source_pin = pin_fixture(source_scene, %{"sheet_id" => source_sheet.id, "flow_id" => source_flow.id})

      source_connection =
        Repo.insert!(%SceneConnection{
          scene_id: source_scene.id,
          from_pin_id: source_pin.id,
          waypoints: []
        })

      {:ok, _source_ambient} =
        Storyarn.Scenes.create_ambient_flow(source_scene.id, %{
          "flow_id" => source_flow.id,
          "trigger_type" => "timed",
          "trigger_config" => %{"interval_ms" => 2_000}
        })

      base_snapshot = active_exact_capture_snapshot(source_project)
      foreign_project = project_fixture(user)
      foreign_sheet = sheet_fixture(foreign_project)
      foreign_flow = flow_fixture(foreign_project)
      foreign_scene = scene_fixture(foreign_project)
      foreign_pin = pin_fixture(foreign_scene)
      missing_pin_id = System.unique_integer([:positive])
      target_project = project_fixture(user, %{name: "Cross-project FK target"})

      cases = [
        {:scene_id,
         update_snapshot_entity(base_snapshot, "flows", source_flow.id, &Map.put(&1, "scene_id", foreign_scene.id)),
         foreign_scene.id},
        {:sheet_id,
         update_snapshot_entity(base_snapshot, "scenes", source_scene.id, fn scene_snapshot ->
           update_scene_pin_snapshot(scene_snapshot, source_pin.id, &Map.put(&1, "sheet_id", foreign_sheet.id))
         end), foreign_sheet.id},
        {:pin_flow_id,
         update_snapshot_entity(base_snapshot, "scenes", source_scene.id, fn scene_snapshot ->
           update_scene_pin_snapshot(scene_snapshot, source_pin.id, &Map.put(&1, "flow_id", foreign_flow.id))
         end), foreign_flow.id},
        {:ambient_flow_id,
         update_snapshot_entity(base_snapshot, "scenes", source_scene.id, fn scene_snapshot ->
           update_in(scene_snapshot, ["ambient_flows"], fn ambient_flows ->
             Enum.map(ambient_flows, &Map.put(&1, "flow_id", foreign_flow.id))
           end)
         end), foreign_flow.id},
        {:connection_pin_id,
         update_snapshot_entity(base_snapshot, "scenes", source_scene.id, fn scene_snapshot ->
           update_in(scene_snapshot, ["connections"], fn connections ->
             Enum.map(connections, fn
               %{"original_id" => id} = connection when id == source_connection.id ->
                 connection
                 |> Map.put("from_layer_index", nil)
                 |> Map.put("from_pin_index", nil)
                 |> Map.put("from_pin_original_id", foreign_pin.id)

               connection ->
                 connection
             end)
           end)
         end), foreign_pin.id},
        {:missing_connection_pin_id,
         update_snapshot_entity(base_snapshot, "scenes", source_scene.id, fn scene_snapshot ->
           update_in(scene_snapshot, ["connections"], fn connections ->
             Enum.map(connections, fn
               %{"original_id" => id} = connection when id == source_connection.id ->
                 connection
                 |> Map.put("from_layer_index", nil)
                 |> Map.put("from_pin_index", nil)
                 |> Map.put("from_pin_original_id", missing_pin_id)

               connection ->
                 connection
             end)
           end)
         end), missing_pin_id}
      ]

      Enum.each(cases, fn {_field, invalid_snapshot, foreign_id} ->
        counts_before = materialized_graph_counts(target_project.id)

        assert {:error, reason} =
                 materialize_snapshot_into_project(
                   target_project,
                   invalid_snapshot,
                   user.id,
                   %{},
                   materialization_mode: :exact
                 )

        assert inspect(reason) =~ Integer.to_string(foreign_id)
        assert materialized_graph_counts(target_project.id) == counts_before
        assert Localization.list_all_texts(target_project.id) == []
      end)
    end

    test "exact materialization accepts authored tree cycles, incomplete coverage, and archived parents", %{
      project: source_project,
      user: user
    } do
      target_project = project_fixture(user, %{name: "Exact authored tree target"})
      target_archived_parent = sheet_fixture(target_project, %{name: "Target archived tree parent"})

      first = sheet_fixture(source_project, %{name: "Cycle first"})
      second = sheet_fixture(source_project, %{name: "Cycle second"})
      omitted = sheet_fixture(source_project, %{name: "Tree entry omitted"})

      archived_child = sheet_fixture(source_project, %{name: "Archived tree child"})

      Repo.update_all(from(sheet in Sheet, where: sheet.id == ^first.id), set: [parent_id: second.id])
      Repo.update_all(from(sheet in Sheet, where: sheet.id == ^second.id), set: [parent_id: first.id])

      Repo.update_all(
        from(sheet in Sheet, where: sheet.id == ^archived_child.id),
        set: [parent_id: target_archived_parent.id]
      )

      Repo.update_all(
        from(sheet in Sheet, where: sheet.id == ^target_archived_parent.id),
        set: [deleted_at: DateTime.utc_now(:second)]
      )

      snapshot_data =
        source_project
        |> active_exact_capture_snapshot()
        |> update_in(["tree", "sheets"], fn entries ->
          Enum.reject(entries, &(&1["id"] == omitted.id))
        end)

      assert {:ok, _materialized_project} =
               materialize_snapshot_into_project(
                 target_project,
                 snapshot_data,
                 user.id,
                 %{},
                 materialization_mode: :exact
               )

      restored_sheets = Storyarn.Sheets.list_all_sheets(target_project.id)
      restored_first = Enum.find(restored_sheets, &(&1.name == "Cycle first"))
      restored_second = Enum.find(restored_sheets, &(&1.name == "Cycle second"))
      restored_omitted = Enum.find(restored_sheets, &(&1.name == "Tree entry omitted"))
      restored_archived_child = Enum.find(restored_sheets, &(&1.name == "Archived tree child"))

      assert restored_first.parent_id == restored_second.id
      assert restored_second.parent_id == restored_first.id
      assert restored_omitted
      assert restored_archived_child.parent_id == target_archived_parent.id
    end

    test "exact materialization rejects cross-project block fallbacks and rolls back", %{
      project: source_project,
      user: user
    } do
      inheritance_source_sheet = sheet_fixture(source_project, %{name: "Foreign inheritance source"})
      authored_sheet = sheet_fixture(source_project, %{name: "Authored inheritance"})
      foreign_block = block_fixture(inheritance_source_sheet, %{type: "text"})

      _authored_block =
        block_fixture(authored_sheet, %{
          type: "text",
          inherited_from_block_id: foreign_block.id
        })

      Repo.update_all(
        from(block in Block, where: block.id == ^foreign_block.id),
        set: [deleted_at: DateTime.utc_now(:second)]
      )

      snapshot_data = active_exact_capture_snapshot(source_project)
      target_project = project_fixture(user, %{name: "Cross-project block target"})
      counts_before = materialized_graph_counts(target_project.id)

      assert {:error, {:exact_snapshot_fk_not_materializable, :block, :inherited_from_block_id, foreign_block_id}} =
               materialize_snapshot_into_project(
                 target_project,
                 snapshot_data,
                 user.id,
                 %{},
                 materialization_mode: :exact
               )

      assert foreign_block_id == foreign_block.id
      assert materialized_graph_counts(target_project.id) == counts_before
      assert Localization.list_all_texts(target_project.id) == []
    end

    test "exact materialization rejects authored localization identities owned by another project", %{
      project: source_project,
      user: user
    } do
      source_language_fixture(source_project, %{locale_code: "en", name: "English"})
      language_fixture(source_project, %{locale_code: "es", name: "Spanish"})
      source_sheet = sheet_fixture(source_project, %{name: "Foreign localization source"})

      foreign_block =
        block_fixture(source_sheet, %{
          type: "rich_text",
          value: %{"content" => "Foreign archived source"}
        })

      assert [_text] = Localization.get_texts_for_source("block", foreign_block.id)

      Repo.update_all(
        from(block in Block, where: block.id == ^foreign_block.id),
        set: [deleted_at: DateTime.utc_now(:second)]
      )

      snapshot_data = active_exact_capture_snapshot(source_project)
      target_project = project_fixture(user, %{name: "Cross-project localization target"})
      counts_before = materialized_graph_counts(target_project.id)

      assert {:error, {:localized_text_materialization_failed, {1, nil}}} =
               materialize_snapshot_into_project(
                 target_project,
                 snapshot_data,
                 user.id,
                 %{},
                 materialization_mode: :exact
               )

      assert materialized_graph_counts(target_project.id) == counts_before
      assert Localization.list_all_texts(target_project.id) == []
      assert Repo.get!(Block, foreign_block.id).sheet_id == source_sheet.id
    end

    test "exact materialization rejects cross-project localization speakers and rolls back", %{
      project: source_project,
      user: user
    } do
      {_sheet, block} = localized_block_fixture(source_project)
      foreign_speaker = sheet_fixture(source_project, %{name: "Foreign archived speaker"})
      [text] = Localization.get_texts_for_source("block", block.id)

      Repo.update_all(
        from(text_row in LocalizedText, where: text_row.id == ^text.id),
        set: [speaker_sheet_id: foreign_speaker.id]
      )

      Repo.update_all(
        from(sheet in Sheet, where: sheet.id == ^foreign_speaker.id),
        set: [deleted_at: DateTime.utc_now(:second)]
      )

      TextCrud.archive_texts_for_sources("sheet", [foreign_speaker.id], "source_deleted")

      snapshot_data = active_exact_capture_snapshot(source_project)
      target_project = project_fixture(user, %{name: "Cross-project speaker target"})
      counts_before = materialized_graph_counts(target_project.id)

      assert {:error, {:exact_snapshot_fk_not_materializable, :localized_text, :speaker_sheet_id, foreign_speaker_id}} =
               materialize_snapshot_into_project(
                 target_project,
                 snapshot_data,
                 user.id,
                 %{},
                 materialization_mode: :exact
               )

      assert foreign_speaker_id == foreign_speaker.id
      assert materialized_graph_counts(target_project.id) == counts_before
      assert Localization.list_all_texts(target_project.id) == []
    end

    test "rejects archived localized text even when its source is still captured", %{
      project: source_project,
      user: user
    } do
      {_sheet, block} = localized_block_fixture(source_project)
      assert Repo.get!(Block, block.id)

      snapshot_data =
        source_project
        |> canonical_snapshot()
        |> update_in(["localization", "texts"], fn texts ->
          Enum.map(texts, fn text ->
            if localization_snapshot_key(text) == {"block", block.id, "value.content", "es"} do
              Map.put(text, "archived_at", DateTime.to_iso8601(DateTime.utc_now(:second)))
            else
              text
            end
          end)
        end)

      target_project = project_fixture(user)
      counts_before = materialized_graph_counts(target_project.id)

      assert {:error, :archived_project_snapshot_localized_text_not_materializable} =
               ProjectRecovery.validate_materialization_snapshot(snapshot_data)

      assert {:error, :archived_project_snapshot_localized_text_not_materializable} =
               materialize_snapshot_into_project(target_project, snapshot_data, user.id, %{})

      assert materialized_graph_counts(target_project.id) == counts_before
      assert Localization.list_all_texts(target_project.id) == []
    end

    test "rejects an active localized text whose source is absent from the graph", %{
      project: source_project,
      user: user
    } do
      source_language_fixture(source_project, %{locale_code: "en", name: "English"})
      language_fixture(source_project, %{locale_code: "es", name: "Spanish"})
      missing_block_id = System.unique_integer([:positive])

      localized_text_fixture(source_project.id, %{
        source_type: "block",
        source_id: missing_block_id,
        source_field: "value.content",
        source_text: "Orphan runtime text",
        source_text_hash: sha256("Orphan runtime text"),
        locale_code: "es"
      })

      snapshot_data = canonical_snapshot(source_project)
      target_project = project_fixture(user)
      counts_before = materialized_graph_counts(target_project.id)

      expected_error =
        {:missing_project_snapshot_localization_source, "block", missing_block_id, "value.content"}

      assert {:error, ^expected_error} =
               ProjectRecovery.validate_materialization_snapshot(snapshot_data)

      assert {:error, ^expected_error} =
               materialize_snapshot_into_project(target_project, snapshot_data, user.id, %{})

      assert materialized_graph_counts(target_project.id) == counts_before
      assert Localization.list_all_texts(target_project.id) == []
    end

    test "materializes the full graph into the existing project without changing identity or memberships", %{
      project: source_project,
      user: user
    } do
      parent = sheet_fixture(source_project, %{name: "Archived parent"})
      child = sheet_fixture(source_project, %{name: "Archived child"})
      assert {:ok, _child} = Storyarn.Sheets.move_sheet(child, parent.id, 0)

      referenced_flow = flow_fixture(source_project, %{name: "Archived referenced flow"})

      referenced_exit =
        node_fixture(referenced_flow, %{
          type: "exit",
          data: %{
            "label" => "Archived branch",
            "technical_id" => "archived_branch",
            "exit_mode" => "terminal"
          }
        })

      caller_flow = flow_fixture(source_project, %{name: "Archived caller flow"})

      subflow =
        node_fixture(caller_flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => referenced_flow.id}
        })

      caller_exit =
        caller_flow.id
        |> Storyarn.Flows.list_nodes()
        |> Enum.find(&(&1.type == "exit"))

      _connection =
        Storyarn.FlowsFixtures.connection_fixture(caller_flow, subflow, caller_exit, %{
          source_pin: "exit_#{referenced_exit.id}"
        })

      scene = scene_fixture(source_project, %{name: "Archived scene"})

      _pin =
        pin_fixture(scene, %{
          "label" => "Archived pin",
          "sheet_id" => child.id,
          "flow_id" => caller_flow.id
        })

      snapshot_data = canonical_snapshot(source_project)
      target_project = project_fixture(user, %{name: "Stable target"})
      current_sheet = sheet_fixture(target_project, %{name: "Current root stays"})
      collaborator = user_fixture()
      membership_fixture(target_project, collaborator, "editor")

      identity_before = project_identity(target_project)
      memberships_before = project_membership_state(target_project.id)
      project_count_before = workspace_project_count(target_project.workspace_id)

      assert {:ok, materialized_project} =
               materialize_snapshot_into_project(
                 target_project,
                 snapshot_data,
                 user.id,
                 %{}
               )

      assert project_identity(materialized_project) == identity_before
      assert project_membership_state(target_project.id) == memberships_before
      assert workspace_project_count(target_project.workspace_id) == project_count_before

      materialized_sheets = Storyarn.Sheets.list_all_sheets(target_project.id)
      assert Enum.any?(materialized_sheets, &(&1.id == current_sheet.id))
      new_parent = Enum.find(materialized_sheets, &(&1.name == "Archived parent"))
      new_child = Enum.find(materialized_sheets, &(&1.name == "Archived child"))
      assert new_parent.id != parent.id
      assert new_child.parent_id == new_parent.id

      materialized_flows = Storyarn.Flows.list_flows(target_project.id)
      new_referenced_flow = Enum.find(materialized_flows, &(&1.name == "Archived referenced flow"))
      new_caller_flow = Enum.find(materialized_flows, &(&1.name == "Archived caller flow"))
      new_subflow = Enum.find(Storyarn.Flows.list_nodes(new_caller_flow.id), &(&1.type == "subflow"))

      new_referenced_exit =
        new_referenced_flow.id
        |> Storyarn.Flows.list_nodes()
        |> Enum.find(&((&1.data || %{})["technical_id"] == "archived_branch"))

      new_connection =
        new_caller_flow.id
        |> Storyarn.Flows.list_connections()
        |> Enum.find(&(&1.source_node_id == new_subflow.id))

      assert new_subflow.data["referenced_flow_id"] == new_referenced_flow.id
      assert new_connection.source_pin == "exit_#{new_referenced_exit.id}"

      [new_scene] = Enum.filter(Storyarn.Scenes.list_scenes(target_project.id), &(&1.name == "Archived scene"))
      [new_pin] = Enum.filter(Storyarn.Scenes.list_pins(new_scene.id), &(&1.label == "Archived pin"))
      assert new_pin.sheet_id == new_child.id
      assert new_pin.flow_id == new_caller_flow.id
    end

    test "uses the exact pre-materialized asset identity without storage fallback", %{
      project: source_project,
      user: user
    } do
      source_asset =
        uploaded_asset(
          source_project,
          user,
          "archived-banner.png",
          "archived banner bytes",
          "image/png"
        )

      source_sheet = sheet_fixture(source_project, %{name: "Archived asset sheet"})
      assert {:ok, _sheet} = Storyarn.Sheets.update_sheet(source_sheet, %{banner_asset_id: source_asset.id})

      snapshot_data = canonical_snapshot(source_project)
      target_project = project_fixture(user, %{name: "Asset target"})

      current_decoy =
        %Asset{project_id: target_project.id, uploaded_by_id: user.id}
        |> Asset.create_changeset(%{
          filename: source_asset.filename,
          content_type: source_asset.content_type,
          size: source_asset.size,
          blob_hash: source_asset.blob_hash,
          key: "projects/#{target_project.id}/assets/#{Ecto.UUID.generate()}/decoy-#{source_asset.filename}"
        })
        |> Repo.insert!()

      target_asset =
        %Asset{project_id: target_project.id, uploaded_by_id: user.id}
        |> Asset.create_changeset(%{
          filename: source_asset.filename,
          content_type: source_asset.content_type,
          size: source_asset.size,
          blob_hash: source_asset.blob_hash,
          key: "projects/#{target_project.id}/assets/#{Ecto.UUID.generate()}/#{source_asset.filename}"
        })
        |> Repo.insert!()

      assert {:ok, materialized_project} =
               materialize_snapshot_into_project(
                 target_project,
                 snapshot_data,
                 user.id,
                 %{source_asset.id => target_asset.id}
               )

      assert materialized_project.id == target_project.id

      [restored_sheet] = Storyarn.Sheets.list_all_sheets(target_project.id)
      assert restored_sheet.banner_asset_id == target_asset.id
      refute restored_sheet.banner_asset_id == source_asset.id
      refute restored_sheet.banner_asset_id == current_decoy.id

      assert Repo.aggregate(
               from(asset in Asset,
                 where:
                   asset.project_id == ^target_project.id and
                     asset.blob_hash == ^source_asset.blob_hash
               ),
               :count
             ) == 2
    end

    test "remaps localization voice-over assets through the same pre-materialized identity", %{
      project: source_project,
      user: user
    } do
      source_language_fixture(source_project, %{locale_code: "en", name: "English"})
      language_fixture(source_project, %{locale_code: "es", name: "Spanish"})

      voice_asset =
        uploaded_asset(
          source_project,
          user,
          "archived-voice.mp3",
          "archived voice bytes",
          "audio/mpeg"
        )

      flow = flow_fixture(source_project, %{name: "Archived localized flow"})
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello"}})
      [text] = Localization.get_texts_for_source("flow_node", node.id)

      assert {:ok, _text} =
               Localization.update_text(text, %{
                 translated_text: "Hola",
                 vo_asset_id: voice_asset.id,
                 vo_status: "recorded"
               })

      snapshot_data = canonical_snapshot(source_project)
      assert :ok = ProjectRecovery.validate_materialization_snapshot(snapshot_data)
      target_project = project_fixture(user, %{name: "Localization target"})

      target_voice =
        %Asset{project_id: target_project.id, uploaded_by_id: user.id}
        |> Asset.create_changeset(%{
          filename: voice_asset.filename,
          content_type: voice_asset.content_type,
          size: voice_asset.size,
          blob_hash: voice_asset.blob_hash,
          key: "projects/#{target_project.id}/assets/#{Ecto.UUID.generate()}/#{voice_asset.filename}"
        })
        |> Repo.insert!()

      assert {:ok, materialized_project} =
               materialize_snapshot_into_project(
                 target_project,
                 snapshot_data,
                 user.id,
                 %{voice_asset.id => target_voice.id}
               )

      assert materialized_project.id == target_project.id

      [restored_text] = Localization.list_texts_for_export(target_project.id, ["es"])
      assert restored_text.vo_asset_id == target_voice.id
      assert restored_text.translated_text == "Hola"
    end

    test "preserves existing translator and reviewer identities", %{
      project: source_project,
      user: user
    } do
      source_language_fixture(source_project, %{locale_code: "en", name: "English"})
      language_fixture(source_project, %{locale_code: "es", name: "Spanish"})
      reviewer = user_fixture()
      flow = flow_fixture(source_project, %{name: "Attributed localization"})
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello"}})
      [text] = Localization.get_texts_for_source("flow_node", node.id)

      assert {:ok, _text} =
               Localization.update_text(text, %{
                 translated_text: "Hola",
                 translated_by_id: user.id,
                 reviewed_by_id: reviewer.id
               })

      snapshot_data = canonical_snapshot(source_project)
      target_project = project_fixture(user, %{name: "Attributed target"})

      assert {:ok, _materialized_project} =
               materialize_snapshot_into_project(
                 target_project,
                 snapshot_data,
                 user.id,
                 %{}
               )

      [restored_text] = Localization.list_texts_for_export(target_project.id, ["es"])
      assert restored_text.translated_by_id == user.id
      assert restored_text.reviewed_by_id == reviewer.id
    end

    test "preserves existing actors and nullifies actors deleted after snapshot capture", %{
      project: source_project,
      user: user
    } do
      source_language_fixture(source_project, %{locale_code: "en", name: "English"})
      language_fixture(source_project, %{locale_code: "es", name: "Spanish"})
      deleted_reviewer = Repo.insert!(%User{email: unique_user_email()})
      flow = flow_fixture(source_project, %{name: "Historically attributed localization"})
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello"}})
      [text] = Localization.get_texts_for_source("flow_node", node.id)

      assert {:ok, _text} =
               Localization.update_text(text, %{
                 translated_text: "Hola",
                 translated_by_id: user.id,
                 reviewed_by_id: deleted_reviewer.id
               })

      snapshot_data = canonical_snapshot(source_project)
      [snapshot_text] = snapshot_data["localization"]["texts"]
      assert snapshot_text["translated_by_id"] == user.id
      assert snapshot_text["reviewed_by_id"] == deleted_reviewer.id

      Repo.delete!(deleted_reviewer)
      assert :ok = ProjectRecovery.validate_materialization_snapshot(snapshot_data)

      target_project = project_fixture(user, %{name: "Deleted attribution target"})

      assert {:ok, _materialized_project} =
               materialize_snapshot_into_project(
                 target_project,
                 snapshot_data,
                 user.id,
                 %{}
               )

      [restored_text] = Localization.list_texts_for_export(target_project.id, ["es"])
      assert restored_text.translated_by_id == user.id
      assert restored_text.reviewed_by_id == nil
    end

    test "accepts actor identities nullified before snapshot capture", %{
      project: source_project,
      user: user
    } do
      source_language_fixture(source_project, %{locale_code: "en", name: "English"})
      language_fixture(source_project, %{locale_code: "es", name: "Spanish"})
      deleted_reviewer = Repo.insert!(%User{email: unique_user_email()})
      flow = flow_fixture(source_project, %{name: "Deleted reviewer localization"})
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello"}})
      [text] = Localization.get_texts_for_source("flow_node", node.id)

      assert {:ok, attributed_text} =
               Localization.update_text(text, %{
                 translated_text: "Hola",
                 translated_by_id: user.id,
                 reviewed_by_id: deleted_reviewer.id
               })

      Repo.delete!(deleted_reviewer)
      assert Repo.reload!(attributed_text).reviewed_by_id == nil

      snapshot_data = canonical_snapshot(source_project)
      [snapshot_text] = snapshot_data["localization"]["texts"]
      assert snapshot_text["translated_by_id"] == user.id
      assert snapshot_text["reviewed_by_id"] == nil

      target_project = project_fixture(user, %{name: "Nullified attribution target"})

      assert {:ok, _materialized_project} =
               materialize_snapshot_into_project(
                 target_project,
                 snapshot_data,
                 user.id,
                 %{}
               )

      [restored_text] = Localization.list_texts_for_export(target_project.id, ["es"])
      assert restored_text.translated_by_id == user.id
      assert restored_text.reviewed_by_id == nil
    end

    test "accepts adopted catalog assets that are not referenced by the archived graph", %{
      project: source_project,
      user: user
    } do
      unused_source_asset =
        uploaded_asset(
          source_project,
          user,
          "unused-archive-asset.png",
          "unused archive bytes",
          "image/png"
        )

      snapshot_data = canonical_snapshot(source_project)
      target_project = project_fixture(user, %{name: "Unused asset target"})

      adopted_unused_asset =
        %Asset{project_id: target_project.id, uploaded_by_id: user.id}
        |> Asset.create_changeset(%{
          filename: unused_source_asset.filename,
          content_type: unused_source_asset.content_type,
          size: unused_source_asset.size,
          blob_hash: unused_source_asset.blob_hash,
          key: "projects/#{target_project.id}/assets/#{Ecto.UUID.generate()}/#{unused_source_asset.filename}"
        })
        |> Repo.insert!()

      assert {:ok, materialized_project} =
               materialize_snapshot_into_project(
                 target_project,
                 snapshot_data,
                 user.id,
                 %{unused_source_asset.id => adopted_unused_asset.id}
               )

      assert materialized_project.id == target_project.id
      assert Repo.get!(Asset, adopted_unused_asset.id).project_id == target_project.id
    end

    test "rejects a cross-root cycle during preflight without materializing graph rows", %{
      project: source_project,
      user: user
    } do
      first_flow = flow_fixture(source_project, %{name: "Cycle first"})
      second_flow = flow_fixture(source_project, %{name: "Cycle second"})

      _first_to_second =
        node_fixture(first_flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => second_flow.id}
        })

      second_to_first = node_fixture(second_flow, %{type: "subflow", data: %{}})

      snapshot_data =
        source_project
        |> canonical_snapshot()
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

      target_project = project_fixture(user, %{name: "Atomic target"})
      current_sheet = sheet_fixture(target_project, %{name: "Current graph"})
      counts_before = materialized_graph_counts(target_project.id)

      assert {:error, {:project_snapshot_reference_cycle, :flow, _flow_id}} =
               materialize_snapshot_into_project(
                 target_project,
                 snapshot_data,
                 user.id,
                 %{}
               )

      assert materialized_graph_counts(target_project.id) == counts_before
      assert Repo.get!(Sheet, current_sheet.id).name == "Current graph"
    end

    test "rejects missing asset mappings before inserting graph rows", %{
      project: source_project,
      user: user
    } do
      source_asset =
        uploaded_asset(source_project, user, "missing-map.png", "missing map", "image/png")

      source_sheet = sheet_fixture(source_project, %{name: "Asset coverage"})
      assert {:ok, _sheet} = Storyarn.Sheets.update_sheet(source_sheet, %{banner_asset_id: source_asset.id})

      snapshot_data = canonical_snapshot(source_project)
      target_project = project_fixture(user)

      assert {:error, {:materialized_asset_mapping_mismatch, %{missing: [source_asset_id], unexpected: []}}} =
               materialize_snapshot_into_project(
                 target_project,
                 snapshot_data,
                 user.id,
                 %{}
               )

      assert source_asset_id == source_asset.id
      assert materialized_graph_counts(target_project.id) == %{flows: 0, scenes: 0, sheets: 0}
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

  defp canonical_snapshot(project) do
    project.id
    |> ProjectSnapshotBuilder.build_snapshot()
    |> Jason.encode!()
    |> Jason.decode!()
    |> then(fn snapshot ->
      {:ok, portable} = SnapshotObjectFormat.portable_project(snapshot)
      portable
    end)
    |> Map.put("asset_catalog_refs", snapshot_asset_catalog_refs(project.id))
  end

  defp active_canonical_snapshot(project) do
    {:ok, snapshot} =
      Repo.repeatable_read(fn ->
        ProjectSnapshotBuilder.build_snapshot_in_transaction(project.id,
          localization_scope: :active
        )
      end)

    snapshot
    |> Jason.encode!()
    |> Jason.decode!()
    |> then(fn normalized ->
      {:ok, portable} = SnapshotObjectFormat.portable_project(normalized)
      portable
    end)
    |> Map.put("asset_catalog_refs", snapshot_asset_catalog_refs(project.id))
  end

  defp active_exact_capture_snapshot(project) do
    {:ok, snapshot} =
      Repo.repeatable_read(fn ->
        ProjectSnapshotBuilder.build_canonical_snapshot_in_transaction(project.id,
          localization_scope: :active
        )
      end)

    snapshot
    |> Jason.encode!()
    |> Jason.decode!()
    |> then(fn normalized ->
      {:ok, portable} = SnapshotObjectFormat.portable_project(normalized)
      portable
    end)
    |> Map.put("asset_catalog_refs", snapshot_asset_catalog_refs(project.id))
  end

  defp snapshot_asset_catalog_refs(project_id) do
    project_id
    |> Assets.list_assets_for_export()
    |> Enum.sort_by(&{&1.inserted_at, &1.id})
    |> Enum.with_index(1)
    |> Map.new(fn {asset, index} ->
      {to_string(asset.id), "asset-#{index |> Integer.to_string() |> String.pad_leading(6, "0")}"}
    end)
  end

  defp update_snapshot_entity(snapshot, collection, source_id, update_fun) do
    update_in(snapshot, [collection], fn entries ->
      Enum.map(entries, fn
        %{"id" => id, "snapshot" => entity_snapshot} = entry when id == source_id ->
          Map.put(entry, "snapshot", update_fun.(entity_snapshot))

        entry ->
          entry
      end)
    end)
  end

  defp update_scene_pin_snapshot(scene_snapshot, source_pin_id, update_fun) do
    update_pins = fn pins ->
      Enum.map(pins || [], fn
        %{"original_id" => id} = pin when id == source_pin_id -> update_fun.(pin)
        pin -> pin
      end)
    end

    scene_snapshot
    |> update_in(["orphan_pins"], update_pins)
    |> update_in(["layers"], fn layers ->
      Enum.map(layers || [], &update_in(&1, ["pins"], update_pins))
    end)
  end

  defp project_identity(project) do
    project
    |> Repo.reload!()
    |> Map.take([
      :id,
      :name,
      :slug,
      :description,
      :project_type,
      :project_subtype,
      :project_type_other,
      :settings,
      :auto_version_flows,
      :auto_version_scenes,
      :auto_version_sheets,
      :deleted_at,
      :deleted_by_id,
      :created_from_template_version_id,
      :owner_id,
      :workspace_id
    ])
  end

  defp materialize_snapshot_into_project(project, snapshot_data, user_id, source_id_map, opts \\ []) do
    Repo.transaction(fn ->
      locked_project =
        Repo.one!(
          from(candidate in Project,
            where: candidate.id == ^project.id and is_nil(candidate.deleted_at),
            lock: "FOR UPDATE"
          )
        )

      with {:ok, actor_ids} <-
             ProjectRecovery.lock_materializable_localization_actors(snapshot_data,
               required_actor_ids: [user_id]
             ),
           {:ok, %{project: materialized_project}} <-
             ProjectRecovery.materialize_into_project(
               locked_project,
               snapshot_data,
               user_id,
               source_id_map,
               Keyword.merge(
                 [
                   localization_scope: :active,
                   preserved_localization_actor_ids: actor_ids
                 ],
                 opts
               )
             ) do
        materialized_project
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp project_membership_state(project_id) do
    project_id
    |> Storyarn.Projects.list_project_members()
    |> Enum.map(&{&1.user_id, &1.role})
    |> Enum.sort()
  end

  defp materialized_graph_counts(project_id) do
    %{
      sheets: length(Storyarn.Sheets.list_all_sheets(project_id)),
      scenes: length(Storyarn.Scenes.list_scenes(project_id)),
      flows: length(Storyarn.Flows.list_flows(project_id))
    }
  end
end
