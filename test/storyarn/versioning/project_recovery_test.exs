defmodule Storyarn.Versioning.ProjectRecoveryTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Assets
  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Localization
  alias Storyarn.ProjectTemplates.Audit
  alias Storyarn.Repo
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Versioning.Builders.ProjectSnapshotBuilder
  alias Storyarn.Versioning.ProjectRecovery

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
      speaker = sheet_fixture(project, %{name: "Speaker Sheet"})
      scene = scene_fixture(project, %{name: "World Map"})
      target_scene = scene_fixture(project, %{name: "Dungeon Map"})
      flow = flow_fixture(project, %{name: "Main Flow"})
      subflow = flow_fixture(project, %{name: "Sub Flow"})

      {:ok, flow} = Storyarn.Flows.update_flow(flow, %{scene_id: scene.id})

      _dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => speaker.id,
            "location_sheet_id" => speaker.id,
            "text" => "Hello"
          }
        })

      _subflow_node =
        node_fixture(flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => subflow.id}
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
      recovered_pin = Enum.find(recovered_scene.pins, &(&1.label == "Gate"))
      recovered_zone = Enum.find(recovered_scene.zones, &(&1.name == "Portal"))

      assert recovered_flow.scene_id == recovered_scene.id
      assert recovered_pin.sheet_id == recovered_speaker.id
      assert recovered_pin.flow_id == recovered_flow.id
      assert recovered_zone.target_id == recovered_target_scene.id
      assert recovered_dialogue.data["speaker_sheet_id"] == recovered_speaker.id
      assert recovered_dialogue.data["location_sheet_id"] == recovered_speaker.id
      assert recovered_subflow_node.data["referenced_flow_id"] == recovered_subflow.id
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

      assert {:error, {:unremappable_subflow_exit_pin, %{connection_id: connection_id, source_pin: source_pin}}} =
               ProjectRecovery.recover_project(workspace_id, snapshot_data, user.id)

      assert connection_id == connection.id
      assert source_pin == "exit_#{referenced_exit.id}"

      refute Repo.exists?(
               from project in Storyarn.Projects.Project,
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

      text =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_id: node.id,
          source_field: "text",
          source_text: "Hello",
          locale_code: "es",
          translated_text: "Hola"
        })

      {:ok, _text} = Localization.update_text(text, %{vo_asset_id: voice_asset.id, vo_status: "recorded"})

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

      Assets.storage_delete(
        BlobStore.blob_key(project.id, asset.blob_hash, BlobStore.ext_from_content_type(content_type))
      )
    end)

    asset
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
