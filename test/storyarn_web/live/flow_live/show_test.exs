defmodule StoryarnWeb.FlowLive.ShowTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Phoenix.LiveView.Socket
  alias Storyarn.Flows
  alias Storyarn.Repo
  alias StoryarnWeb.FlowLive.Show
  alias StoryarnWeb.FlowSidebarLive

  describe "flow editor layout" do
    setup :register_and_log_in_user

    test "renders header, surface, and panels on the canonical route",
         %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Canonical Flow"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_async(view, 2000)

      surface = LiveVue.Test.get_vue(view, name: "live/flow/show/FlowSurface")
      panels = LiveVue.Test.get_vue(view, name: "live/flow/show/FlowPanels")
      header = LiveVue.Test.get_vue(view, name: "live/flow/show/FlowHeader")

      assert header.props["flow-name"] == "Canonical Flow"
      assert surface.props["surface"]["canvas"]["canvasId"] == "flow-canvas-#{flow.id}"
      assert surface.props["surface"]["dock"]["flowId"] == flow.id
      assert surface.props["surface"]["stage"] == %{"status" => "empty"}
      assert surface.props["surface"]["debug"]["open"] == false
      refute Map.has_key?(panels.props["panels"], "debug")
    end

    test "selecting a dialogue resolves its inherited composition in the Sequence stage",
         %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Sequence Stage Flow"})
      backdrop = image_asset_fixture(project, user, %{filename: "stage-room.png"})

      {:ok, sequence} = Flows.create_sequence(flow.id, %{"name" => "Shared scene"})

      {:ok, _layer} =
        Flows.create_sequence_visual_layer(sequence.id, %{
          asset_id: backdrop.id,
          kind: "backdrop",
          label: "Room"
        })

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          parent_id: sequence.id,
          data: %{"text" => "<p>The door opens.</p>", "responses" => []}
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_async(view, 2000)
      render_hook(view, "node_selected", %{"id" => dialogue.id})
      render(view)

      surface = LiveVue.Test.get_vue(view, name: "live/flow/show/FlowSurface")
      stage = surface.props["surface"]["stage"]

      assert stage["status"] == "ready"
      assert stage["intervention"]["nodeId"] == dialogue.id
      assert stage["intervention"]["text"] == "<p>The door opens.</p>"
      assert [%{"label" => "Room", "origin" => origin}] = stage["composition"]["layers"]
      assert origin == %{"inherited" => true, "nodeId" => sequence.id, "sequenceId" => sequence.id}
    end

    test "debug Stage and composition share the branch speaker through convergence, back, and reset",
         %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Debug presentation flow"})
      full_flow = Flows.get_flow!(project.id, flow.id)
      entry = Enum.find(full_flow.nodes, &(&1.type == "entry"))
      exit_node = Enum.find(full_flow.nodes, &(&1.type == "exit"))

      first =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "<p>Before condition</p>", "responses" => []}
        })

      condition =
        node_fixture(flow, %{
          type: "condition",
          data: %{"condition" => %{"logic" => "all", "rules" => []}}
        })

      true_branch =
        node_fixture(flow, %{
          type: "dialogue",
          composition_source_id: first.id,
          data: %{"text" => "<p>True branch</p>", "responses" => []}
        })

      false_branch =
        node_fixture(flow, %{
          type: "dialogue",
          composition_source_id: first.id,
          data: %{"text" => "<p>False branch</p>", "responses" => []}
        })

      convergence = node_fixture(flow, %{type: "hub", data: %{"hub_id" => "join"}})
      first_asset = image_asset_fixture(project, user, %{filename: "before-condition.png"})
      branch_asset = image_asset_fixture(project, user, %{filename: "true-branch.png"})

      {:ok, first_layer} =
        Flows.create_sequence_visual_layer(first.id, %{
          asset_id: first_asset.id,
          kind: "backdrop",
          label: "Before"
        })

      {:ok, branch_layer} =
        Flows.create_sequence_visual_layer(true_branch.id, %{
          asset_id: branch_asset.id,
          kind: "character",
          label: "True branch"
        })

      connection_fixture(flow, entry, first)
      connection_fixture(flow, first, condition)
      connection_fixture(flow, condition, true_branch, %{source_pin: "true"})
      connection_fixture(flow, condition, false_branch, %{source_pin: "false"})
      connection_fixture(flow, true_branch, convergence)
      connection_fixture(flow, false_branch, convergence)
      connection_fixture(flow, convergence, exit_node)

      source_language_fixture(project, %{locale_code: "en", name: "English"})
      language_fixture(project, %{locale_code: "es", name: "Spanish"})
      localize_debug_dialogue(project.id, first, "<p>Antes de la condición</p>")
      localize_debug_dialogue(project.id, true_branch, "<p>Rama verdadera</p>")

      url = ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
      view = mount_flow(conn, url)
      render_click(view, "set_sequence_content_locale", %{"locale" => "es"})
      render_click(view, "debug_start", %{})

      surface = flow_surface(view)
      assert surface["stage"] == %{"status" => "empty"}
      assert surface["debug"]["composition"] == nil

      render_click(view, "debug_step", %{})
      assert_debug_presentation(view, first.id, "<p>Antes de la condición</p>", [first_layer.layer_key])

      render_click(view, "debug_step", %{})
      surface = flow_surface(view)
      assert surface["debug"]["state"]["current_node_id"] == condition.id
      assert_debug_presentation(view, first.id, "<p>Antes de la condición</p>", [first_layer.layer_key])

      render_click(view, "debug_step", %{})

      assert_debug_presentation(
        view,
        true_branch.id,
        "<p>Rama verdadera</p>",
        [first_layer.layer_key, branch_layer.layer_key]
      )

      render_click(view, "debug_step", %{})
      surface = flow_surface(view)
      assert surface["debug"]["state"]["current_node_id"] == convergence.id

      assert_debug_presentation(
        view,
        true_branch.id,
        "<p>Rama verdadera</p>",
        [first_layer.layer_key, branch_layer.layer_key]
      )

      render_click(view, "debug_step_back", %{})

      assert_debug_presentation(
        view,
        true_branch.id,
        "<p>Rama verdadera</p>",
        [first_layer.layer_key, branch_layer.layer_key]
      )

      render_click(view, "debug_step_back", %{})
      assert_debug_presentation(view, first.id, "<p>Antes de la condición</p>", [first_layer.layer_key])

      render_click(view, "debug_reset", %{})
      surface = flow_surface(view)
      assert surface["stage"] == %{"status" => "empty"}
      assert surface["debug"]["composition"] == nil
    end

    test "opens the composition inspector for the owner requested by the Sequence stage",
         %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Inspector owner flow"})
      first = node_fixture(flow, %{type: "dialogue", data: %{"text" => "First"}})
      second = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Second"}})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_async(view, 2000)
      render_hook(view, "node_selected", %{"id" => first.id})
      render_hook(view, "open_sequence_config", %{"id" => second.id})
      render(view)

      panels = LiveVue.Test.get_vue(view, name: "live/flow/show/FlowPanels")
      surface = LiveVue.Test.get_vue(view, name: "live/flow/show/FlowSurface")

      assert panels.props["panels"]["sequence"]["open"] == true
      assert panels.props["panels"]["sequence"]["data"]["owner_id"] == second.id
      assert surface.props["surface"]["stage"]["owner"]["nodeId"] == second.id
    end

    test "restoring another owner's history keeps the selected stage and inspector aligned",
         %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Independent history owners"})
      {:ok, first} = Flows.create_sequence(flow.id, %{"name" => "First before"})

      second =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "<p>Second stays selected</p>", "responses" => []}
        })

      assert {:ok, before} = Flows.capture_sequence_composition(first.id)
      assert {:ok, _updated_first} = Flows.update_sequence(first, %{"name" => "First after"})
      assert {:ok, current} = Flows.capture_sequence_composition(first.id)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_async(view, 2000)
      render_hook(view, "open_sequence_config", %{"id" => second.id})

      render_hook(view, "restore_sequence_composition", %{
        "id" => first.id,
        "snapshot" => before,
        "expected_current" => current
      })

      panels = LiveVue.Test.get_vue(view, name: "live/flow/show/FlowPanels")
      surface = LiveVue.Test.get_vue(view, name: "live/flow/show/FlowSurface")

      assert panels.props["panels"]["sequence"]["data"]["owner_id"] == second.id
      assert surface.props["surface"]["stage"]["owner"]["nodeId"] == second.id

      assert surface.props["surface"]["stage"]["intervention"]["text"] ==
               "<p>Second stays selected</p>"

      assert Flows.get_sequence_config(first.id).name == "First before"
    end

    test "invalidates client history when a composition restore cannot be applied",
         %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Composition history conflicts"})
      {:ok, owner} = Flows.create_sequence(flow.id, %{"name" => "Before"})

      assert {:ok, before} = Flows.capture_sequence_composition(owner.id)
      assert {:ok, owner} = Flows.update_sequence(owner, %{"name" => "Expected"})
      assert {:ok, expected} = Flows.capture_sequence_composition(owner.id)
      assert {:ok, _owner} = Flows.update_sequence(owner, %{"name" => "Intervening edit"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_async(view, 2000)

      render_hook(view, "restore_sequence_composition", %{
        "id" => owner.id,
        "snapshot" => before,
        "expected_current" => expected
      })

      assert_push_event(view, "sequence_composition_history_invalidated", %{})

      render_hook(view, "restore_sequence_composition", %{
        "id" => owner.id,
        "snapshot" => before
      })

      assert_push_event(view, "sequence_composition_history_invalidated", %{})

      foreign_flow = flow_fixture(project, %{name: "Foreign composition owner"})
      {:ok, foreign_owner} = Flows.create_sequence(foreign_flow.id, %{"name" => "Foreign"})
      assert {:ok, foreign_snapshot} = Flows.capture_sequence_composition(foreign_owner.id)

      render_hook(view, "restore_sequence_composition", %{
        "id" => foreign_owner.id,
        "snapshot" => foreign_snapshot,
        "expected_current" => foreign_snapshot
      })

      assert_push_event(view, "sequence_composition_history_invalidated", %{})
      assert Flows.get_sequence_config(owner.id).name == "Intervening edit"
    end

    test "the inspector exposes tombstones inherited from an ancestor for restoration",
         %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Inherited tombstones"})
      image = image_asset_fixture(project, user)
      audio = audio_asset_fixture(project, user)
      {:ok, base} = Flows.create_sequence(flow.id, %{"name" => "Base"})

      middle =
        node_fixture(flow, %{
          type: "dialogue",
          composition_source_id: base.id,
          data: %{"text" => "Middle"}
        })

      descendant =
        node_fixture(flow, %{
          type: "dialogue",
          composition_source_id: middle.id,
          data: %{"text" => "Descendant"}
        })

      {:ok, layer} =
        Flows.create_sequence_visual_layer(base.id, %{
          "kind" => "backdrop",
          "asset_id" => image.id
        })

      {:ok, track} =
        Flows.upsert_sequence_track(base.id, "ambience", %{
          "asset_id" => audio.id
        })

      assert {:ok, %{removed: true}} =
               Flows.remove_sequence_visual_layer(middle.id, layer.layer_key)

      assert {:ok, %{removed: true}} =
               Flows.remove_sequence_track(middle.id, track.track_key)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_async(view, 2000)
      render_hook(view, "open_sequence_config", %{"id" => descendant.id})
      render(view)

      data =
        view
        |> LiveVue.Test.get_vue(name: "live/flow/show/FlowPanels")
        |> then(& &1.props["panels"]["sequence"]["data"])

      removed_layer =
        Enum.find(data["removed_visual_layers"], &(&1["key"] == layer.layer_key))

      removed_track =
        Enum.find(data["removed_tracks"], &(&1["trackKey"] == track.track_key))

      assert removed_layer["removed"] == true
      assert removed_layer["local_row_id"] == nil
      assert removed_layer["asset_id"] == image.id
      assert removed_track["removed"] == true
      assert removed_track["local_row_id"] == nil
      assert removed_track["asset_id"] == audio.id

      assert {:ok, restored_layer} =
               Flows.restore_sequence_visual_layer(descendant.id, layer.layer_key)

      assert {:ok, restored_track} =
               Flows.restore_sequence_track(descendant.id, track.track_key)

      render_hook(view, "open_sequence_config", %{"id" => descendant.id})
      render(view)

      restored_data =
        view
        |> LiveVue.Test.get_vue(name: "live/flow/show/FlowPanels")
        |> then(& &1.props["panels"]["sequence"]["data"])

      effective_layer =
        Enum.find(restored_data["visual_layers"], &(&1["key"] == layer.layer_key))

      effective_track =
        Enum.find(restored_data["tracks"], &(&1["trackKey"] == track.track_key))

      assert effective_layer["sequenceId"] == descendant.id
      assert effective_layer["local_row_id"] == restored_layer.id
      assert effective_track["sequenceId"] == descendant.id
      assert effective_track["local_row_id"] == restored_track.id
      assert effective_track["isOverride"] == true

      assert {:ok, _deleted_layer} =
               Flows.remove_sequence_visual_layer(descendant.id, layer.layer_key)

      assert {:ok, _deleted_track} =
               Flows.remove_sequence_track(descendant.id, track.track_key)

      assert is_nil(Flows.get_sequence_visual_layer_by_key(descendant.id, layer.layer_key))
      assert is_nil(Flows.get_sequence_track_by_key(descendant.id, track.track_key))

      render_hook(view, "open_sequence_config", %{"id" => descendant.id})
      render(view)

      removed_again =
        view
        |> LiveVue.Test.get_vue(name: "live/flow/show/FlowPanels")
        |> then(& &1.props["panels"]["sequence"]["data"])

      assert Enum.any?(
               removed_again["removed_visual_layers"],
               &(&1["key"] == layer.layer_key and is_nil(&1["local_row_id"]))
             )

      assert Enum.any?(
               removed_again["removed_tracks"],
               &(&1["trackKey"] == track.track_key and is_nil(&1["local_row_id"]))
             )
    end

    test "reports composition dependency conflicts instead of silently ignoring them",
         %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Protected composition"})
      image = image_asset_fixture(project, user)
      {:ok, base} = Flows.create_sequence(flow.id, %{"name" => "Base"})

      descendant =
        node_fixture(flow, %{
          type: "dialogue",
          composition_source_id: base.id,
          data: %{"text" => "Customized"}
        })

      {:ok, layer} =
        Flows.create_sequence_visual_layer(base.id, %{
          "kind" => "character",
          "asset_id" => image.id
        })

      assert {:ok, _patch} =
               Flows.override_sequence_visual_layer(descendant.id, layer.layer_key, %{
                 "opacity" => 0.5
               })

      url = ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
      view = mount_flow(conn, url)

      render_hook(view, "delete_sequence_visual_layer", %{
        "id" => base.id,
        "layer_id" => layer.id
      })

      flash = LiveVue.Test.get_vue(view, name: "live/layouts/flash/FlashGroup")

      assert flash.props["flash"]["error"] ==
               "This composition or one of its descendants still depends on that source, layer, or audio track. Reassign or revert those local changes first."

      assert Flows.get_sequence_visual_layer(base.id, layer.id)
    end

    test "a viewer can change the content locale without gaining edit access", %{conn: conn, user: user} do
      owner = Storyarn.AccountsFixtures.user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      membership_fixture(project, user, "viewer")
      source_language_fixture(project, %{locale_code: "en", name: "English"})
      language_fixture(project, %{locale_code: "es", name: "Spanish"})
      flow = flow_fixture(project, %{name: "Localized Sequence Stage"})

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "<p>Hello</p>", "responses" => []}
        })

      source_hash = :sha256 |> :crypto.hash("<p>Hello</p>") |> Base.encode16(case: :lower)

      localized_text_fixture(project.id, %{
        source_id: dialogue.id,
        source_field: "text",
        source_text: "<p>Hello</p>",
        source_text_hash: source_hash,
        translated_source_hash: source_hash,
        translated_text: "<p>Hola</p>",
        status: "draft"
      })

      url = ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
      view = mount_flow(conn, url)
      render_hook(view, "node_selected", %{"id" => dialogue.id})
      render(view)
      render_click(view, "set_sequence_content_locale", %{"locale" => "es"})

      stage =
        view
        |> LiveVue.Test.get_vue(name: "live/flow/show/FlowSurface")
        |> then(& &1.props["surface"]["stage"])

      assert stage["contentLocale"] == "es"
      assert stage["intervention"]["text"] == "<p>Hola</p>"
      assert stage["intervention"]["localization"]["fallback"] == false
    end

    test "passes incomplete dialogue findings to the warning section",
         %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Warnings Flow"})

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "<p><br></p>", "responses" => []}
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_async(view, 2000)

      header = LiveVue.Test.get_vue(view, name: "live/flow/show/FlowHeader")
      health = header.props["flow-health"]["health"]
      item = Enum.find(health["warningItems"], &(&1["entityId"] == dialogue.id))
      codes = Enum.map(item["reasons"], & &1["code"])

      # Codes cross the wire, not sentences: Vue resolves them against
      # `flows.health.findings.*`, the same catalog the dashboard uses.
      assert "missing_dialogue_text" in codes
      assert "missing_dialogue_speaker" in codes
      refute Enum.any?(health["errorItems"], &(&1["entityId"] == dialogue.id))
    end

    test "exposes the current speaker through the preview panel", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Preview Flow"})
      speaker = sheet_fixture(project, %{name: "Ada Lovelace"})

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "<p>Hello from preview</p>",
            "speaker_sheet_id" => speaker.id,
            "responses" => []
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_async(view, 2000)
      render_click(view, "start_preview", %{"id" => dialogue.id})

      panels = LiveVue.Test.get_vue(view, name: "live/flow/show/FlowPanels")
      preview = panels.props["panels"]["preview"]

      assert preview["open"] == true
      assert preview["currentNode"]["speaker"] == "Ada Lovelace"
      assert preview["currentNode"]["speakerInitials"] == "AL"
    end

    test "compact route keeps the canvas boundary mounted while data loads",
         %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Compact Flow"})

      {:ok, view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}?layout=compact"
        )

      layout = LiveVue.Test.get_vue(html, name: "live/layouts/compare/Layout")
      initial_canvas = LiveVue.Test.get_vue(html, name: "live/flow/show/FlowCanvas")

      assert layout.id == "compare-layout"
      assert initial_canvas.id == "flow-editor-compact-#{flow.id}"
      assert initial_canvas.props["loading"] == true
      assert initial_canvas.props["flow-data"] == nil

      render_async(view, 2000)

      loaded_canvas = LiveVue.Test.get_vue(view, name: "live/flow/show/FlowCanvas")

      assert loaded_canvas.props["loading"] == false
      assert loaded_canvas.props["flow-data"] =~ "Compact Flow"
      assert loaded_canvas.props["canvas-id"] == "flow-canvas-#{flow.id}"
    end
  end

  describe "canvas navigation events" do
    setup :register_and_log_in_user

    setup %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Navigation Flow"})
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hi", "responses" => []}})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}")

      render_async(view, 2000)

      %{view: view, node: node}
    end

    # The Vitest test asserts only that the health popover SENDS `navigate_to_node`.
    # Nothing asserted the server ANSWERS it, so deleting the handler would have
    # broken nothing that `mix precommit` runs. Each of the three handlers uses a
    # DIFFERENT payload key, so swapping two of them is silent today.
    test "navigate_to_node answers with the node's db id", %{view: view, node: node} do
      node_id = node.id

      render_hook(view, "navigate_to_node", %{"id" => node_id})

      assert_push_event(view, "navigate_to_node", %{node_db_id: ^node_id})
    end

    test "navigate_to_node accepts the id as a string", %{view: view, node: node} do
      node_id = node.id

      render_hook(view, "navigate_to_node", %{"id" => to_string(node_id)})

      assert_push_event(view, "navigate_to_node", %{node_db_id: ^node_id})
    end

    test "navigate_to_node ignores an unparseable id without crashing", %{view: view} do
      render_hook(view, "navigate_to_node", %{"id" => "42abc"})

      assert render(view) =~ "Navigation Flow"
      refute_push_event(view, "navigate_to_node", %{})
    end

    test "navigate_to_hub and navigate_to_jumps keep their own payload keys", %{
      view: view,
      node: node
    } do
      node_id = node.id

      render_hook(view, "navigate_to_hub", %{"id" => node_id})
      assert_push_event(view, "navigate_to_hub", %{jump_db_id: ^node_id})

      render_hook(view, "navigate_to_jumps", %{"id" => node_id})
      assert_push_event(view, "navigate_to_jumps", %{hub_db_id: ^node_id})
    end
  end

  describe "dashboard deep link" do
    setup :register_and_log_in_user

    test "?highlight=node:<id> focuses the offending node", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Highlighted Flow"})
      dialogue = node_fixture(flow, %{type: "dialogue", data: %{"text" => ""}})
      base = ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"

      {:ok, view, _html} = live(conn, base)
      render_async(view, 2000)

      render_patch(view, "#{base}?highlight=node:#{dialogue.id}")

      dialogue_id = dialogue.id
      assert_push_event(view, "navigate_to_node", %{node_db_id: ^dialogue_id})
    end

    test "a malformed highlight is ignored", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Unhighlighted Flow"})
      base = ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"

      {:ok, view, _html} = live(conn, base)
      render_async(view, 2000)

      render_patch(view, "#{base}?highlight=zone:not-a-node")

      refute_push_event(view, "navigate_to_node", %{})
    end
  end

  describe "async flow loading" do
    setup :register_and_log_in_user

    test "ignores stale load results after navigating to another flow", %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      current_flow = flow_fixture(project, %{name: "Current Flow"})
      stale_flow = flow_fixture(project, %{name: "Stale Flow"})

      socket = %Socket{
        assigns: %{
          __changed__: %{},
          flow: current_flow,
          loading: true,
          selected_node: :keep
        }
      }

      {:noreply, result} =
        Show.handle_async(:load_flow_data, {:ok, %{flow: stale_flow}}, socket)

      assert result.assigns.flow.id == current_flow.id
      assert result.assigns.loading == true
      assert result.assigns.selected_node == :keep
    end
  end

  describe "Hub color events" do
    setup :register_and_log_in_user

    test "updates the selected Hub with a valid picker color", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Colored Hub Flow"})

      hub =
        node_fixture(flow, %{
          type: "hub",
          data: %{"hub_id" => "checkpoint", "color" => "#be185d"}
        })

      url = ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
      view = mount_flow(conn, url)

      render_click(view, "node_selected", %{"id" => hub.id})
      render_click(view, "update_hub_color", %{"color" => "#22c55e"})

      assert Flows.get_node!(flow.id, hub.id).data["color"] == "#22c55e"
    end

    test "rejects a legacy named picker color from the current contract",
         %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Validated Hub Flow"})

      hub =
        node_fixture(flow, %{
          type: "hub",
          data: %{"hub_id" => "checkpoint", "color" => "#3b82f6"}
        })

      url = ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
      view = mount_flow(conn, url)

      render_click(view, "node_selected", %{"id" => hub.id})
      render_click(view, "update_hub_color", %{"color" => "blue"})

      assert Flows.get_node!(flow.id, hub.id).data["color"] == Flows.hub_color_default_hex()
    end

    test "ignores Hub color events when the selected node is not a Hub",
         %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Non-Hub Color Flow"})

      _hub =
        node_fixture(flow, %{
          type: "hub",
          data: %{"hub_id" => "checkpoint", "color" => "#3b82f6"}
        })

      jump = node_fixture(flow, %{type: "jump", data: %{"target_hub_id" => "checkpoint"}})

      url = ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
      view = mount_flow(conn, url)

      render_click(view, "node_selected", %{"id" => jump.id})
      render_click(view, "update_hub_color", %{"color" => "#22c55e"})

      assert Flows.get_node!(flow.id, jump.id).data == %{"target_hub_id" => "checkpoint"}
    end

    test "does not let a viewer update a Hub color", %{conn: conn, user: user} do
      owner = Storyarn.AccountsFixtures.user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      flow = flow_fixture(project, %{name: "Viewer Hub Color Flow"})

      hub =
        node_fixture(flow, %{
          type: "hub",
          data: %{"hub_id" => "checkpoint", "color" => "#be185d"}
        })

      url = ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
      view = mount_flow(conn, url)

      render_click(view, "node_selected", %{"id" => hub.id})
      render_click(view, "update_hub_color", %{"color" => "#22c55e"})

      assert Flows.get_node!(flow.id, hub.id).data["color"] == "#be185d"
    end
  end

  describe "picker search" do
    setup :register_and_log_in_user

    test "routes Sheet speaker searches through the Flows-owned catalog", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Speaker Picker Flow"})
      speaker = sheet_fixture(project, %{name: "Hero Speaker", shortcut: "hero"})
      speaker_id = speaker.id
      url = ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
      view = mount_flow(conn, url)

      render_hook(view, "picker_search", %{
        "resource" => "entity",
        "kind" => "sheet",
        "query" => "hero",
        "limit" => 10,
        "request_id" => "speaker-search"
      })

      assert_push_event(view, "picker_search_results", %{
        request_id: "speaker-search",
        results: [%{id: ^speaker_id, name: "Hero Speaker"}],
        has_more: false
      })
    end
  end

  describe "Flow sidebar autonomy" do
    setup :register_and_log_in_user

    test "uses the canonical membership for every mutation even if can_edit is stale" do
      socket = %Socket{
        assigns: %{
          __changed__: %{},
          flash: %{},
          membership: %{role: "viewer"},
          can_edit: true
        }
      }

      mutations = [
        {"create_flow", %{}},
        {"create_child_flow", %{"parent_id" => "1"}},
        {"set_main_flow", %{"id" => "1"}},
        {"set_pending_delete_flow", %{"id" => "1"}},
        {"confirm_delete_flow", %{}},
        {"move_to_parent", %{"item_id" => "1", "new_parent_id" => nil, "position" => 0}}
      ]

      for {event, params} <- mutations do
        assert {:noreply, result} = FlowSidebarLive.handle_event(event, params, socket)

        assert result.assigns.flash["error"] ==
                 "You don't have permission to perform this action."

        refute Map.has_key?(result.assigns, :pending_delete_id)
      end
    end

    test "moves a Flow without requiring a Project schema assign", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      current = flow_fixture(project, %{name: "Current"})
      parent = flow_fixture(project, %{name: "Parent"})
      child = flow_fixture(project, %{name: "Child"})
      url = ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{current.id}"
      view = mount_flow(conn, url)
      sidebar = find_live_child(view, "sidebar-flows-#{project.id}")

      render_click(sidebar, "move_to_parent", %{
        "item_id" => child.id,
        "new_parent_id" => parent.id,
        "position" => 0
      })

      assert Flows.get_flow(project.id, child.id).parent_id == parent.id
    end

    test "moves a Flow to trash without requiring a Project schema assign", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      current = flow_fixture(project, %{name: "Current"})
      victim = flow_fixture(project, %{name: "Victim"})
      url = ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{current.id}"
      view = mount_flow(conn, url)
      sidebar = find_live_child(view, "sidebar-flows-#{project.id}")

      render_click(sidebar, "set_pending_delete_flow", %{"id" => victim.id})
      render_click(sidebar, "confirm_delete_flow")

      assert Flows.get_flow(project.id, victim.id) == nil
    end
  end

  describe "version history events" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "History Flow"})
      url = ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"

      %{project: project, flow: flow, url: url}
    end

    test "publishes and refreshes named-version capacity in the Flow panel", %{
      conn: conn,
      user: user,
      url: url,
      flow: flow
    } do
      for number <- 1..9 do
        assert {:ok, _version} =
                 Flows.create_version(flow, user.id,
                   title: "Checkpoint #{number}",
                   skip_diff: true
                 )
      end

      view = mount_flow(conn, url)
      render_click(view, "open_versions_panel")

      panels = LiveVue.Test.get_vue(view, name: "live/flow/show/FlowPanels")
      versions = panels.props["panels"]["versions"]

      assert versions["open"]
      assert versions["canNameVersion"]
      assert length(versions["namedVersions"]) == 9

      render_click(view, "create_version", %{
        "title" => "Final free checkpoint",
        "description" => "Consumes the last named-version slot"
      })

      panels = LiveVue.Test.get_vue(view, name: "live/flow/show/FlowPanels")
      versions = panels.props["panels"]["versions"]

      refute versions["canNameVersion"]
      assert length(versions["namedVersions"]) == 10
    end

    test "creates a named version", %{conn: conn, url: url, flow: flow} do
      view = mount_flow(conn, url)

      render_click(view, "create_version", %{
        "title" => "First milestone",
        "description" => "Initial playable flow"
      })

      version = Flows.get_version(flow.id, 1)
      assert version.title == "First milestone"
      assert version.description == "Initial playable flow"
      refute version.is_auto
    end

    test "requires a title", %{conn: conn, url: url, flow: flow} do
      view = mount_flow(conn, url)

      render_click(view, "create_version", %{"title" => "", "description" => "Ignored"})

      assert Flows.count_versions(flow.id) == 0
    end

    test "updates version title and description", %{
      conn: conn,
      user: user,
      url: url,
      flow: flow
    } do
      {:ok, version} = Flows.create_version(flow, user.id, is_auto: true)

      view = mount_flow(conn, url)

      render_click(view, "promote_version", %{
        "version_number" => to_string(version.version_number),
        "title" => "Named checkpoint",
        "description" => "Ready for review"
      })

      updated = Flows.get_version(flow.id, version.version_number)
      assert updated.title == "Named checkpoint"
      assert updated.description == "Ready for review"
    end

    test "deletes an existing version", %{conn: conn, user: user, url: url, flow: flow} do
      {:ok, version} = Flows.create_version(flow, user.id, title: "Disposable")

      view = mount_flow(conn, url)

      render_click(view, "delete_version", %{"version_number" => to_string(version.version_number)})

      refute Flows.get_version(flow.id, version.version_number)
    end

    test "restores the flow from the selected version", %{
      conn: conn,
      user: user,
      project: project,
      url: url,
      flow: flow
    } do
      {:ok, version} = Flows.create_version(flow, user.id, title: "Before rename")

      {:ok, _changed_flow} = Flows.update_flow(flow, %{name: "Changed Flow"})
      view = mount_flow(conn, url)

      render_click(view, "confirm_restore", %{
        "version_number" => to_string(version.version_number),
        "request_id" => "flow-confirm-request"
      })

      assert_push_event(view, "version_restored", %{request_id: "flow-confirm-request"})

      restored = Flows.get_flow(project.id, flow.id)
      assert restored.name == "History Flow"
    end
  end

  defp flow_surface(view) do
    view
    |> LiveVue.Test.get_vue(name: "live/flow/show/FlowSurface")
    |> then(& &1.props["surface"])
  end

  defp assert_debug_presentation(view, node_id, translated_text, expected_layer_keys) do
    surface = flow_surface(view)
    stage = surface["stage"]
    composition = surface["debug"]["composition"]

    assert stage["owner"]["nodeId"] == node_id
    assert stage["contentLocale"] == "es"
    assert stage["intervention"]["text"] == translated_text
    assert composition["presentationNodeId"] == node_id

    stage_keys = stage["composition"]["layers"] |> Enum.map(& &1["key"]) |> Enum.sort()
    debug_keys = composition["visualLayers"] |> Enum.map(& &1["key"]) |> Enum.sort()

    assert stage_keys == Enum.sort(expected_layer_keys)
    assert debug_keys == stage_keys
  end

  defp localize_debug_dialogue(project_id, dialogue, translated_text) do
    source_text = dialogue.data["text"]
    source_hash = :sha256 |> :crypto.hash(source_text) |> Base.encode16(case: :lower)

    localized_text_fixture(project_id, %{
      source_id: dialogue.id,
      source_field: "text",
      source_text: source_text,
      source_text_hash: source_hash,
      translated_source_hash: source_hash,
      translated_text: translated_text,
      status: "draft"
    })
  end

  defp mount_flow(conn, url) do
    {:ok, view, _html} = live(conn, url)
    await_async(view)
    view
  end
end
