defmodule Storyarn.Scenes.DashboardHealthCoverageTest do
  @moduledoc """
  The invariant the scene health consolidation exists for: **the scene editor and
  the scenes dashboard cannot disagree, and the dashboard discriminates against
  no finding.**

  The dashboard used to hand-write nine aggregate SQL detectors covering 9 of the
  36 codes the checker can emit, so 27 kinds of problem were visible only after
  opening the one scene that had them. Now both surfaces enter through
  `Scenes.scene_health_findings/3`; what these tests pin is that they also FEED
  it equivalently — the editor from its socket assigns, the dashboard from
  `HealthSnapshots.load_project/1`'s batched queries.

  Coverage is asserted by CONSTRUCTING all 36, not by reading the source: if
  `load_project/1` forgot a collection or a reference set, the codes that depend
  on it would silently vanish from the union and this test would fail.
  """

  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Assets
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Scenes.HealthChecker
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.SceneLayer
  alias StoryarnWeb.FlowLive.Helpers.VariableHelpers
  alias StoryarnWeb.SceneLive.Helpers.HealthHelpers

  @item_id "d6a3ceec-7a4c-46a4-bd43-073639a8b66c"

  setup do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project, world: build_world(user, project)}
  end

  describe "dashboard coverage" do
    test "emits every code the checker can emit", %{project: project} do
      emitted =
        project.id
        |> Scenes.list_dashboard_health_findings()
        |> MapSet.new(& &1.code)

      declared = MapSet.new(HealthChecker.codes())
      unreachable = declared |> MapSet.difference(emitted) |> MapSet.to_list() |> Enum.sort()

      assert unreachable == [],
             "the dashboard cannot emit #{inspect(unreachable)}, so those problems are only ever " <>
               "visible after opening the one scene that has them"

      assert emitted == declared
    end

    test "every finding is attributed to its own scene and named", %{project: project} do
      findings = Scenes.list_dashboard_health_findings(project.id)

      # A nil scene_id collapses every scene into one dashboard row.
      refute Enum.any?(findings, &is_nil(&1.scene_id))
      assert Enum.all?(findings, &is_binary(&1.details[:scene_name]))

      # The element's own name is what turns "Scene · ?" into "Scene · Lost Pin".
      pin_finding = Enum.find(findings, &(&1.entity_type == "pin" and &1.code == :stale_pin_sheet_reference))
      assert pin_finding.details[:entity_label] == "Stale Sheet Pin"
    end

    test "excludes scenes of other projects and soft-deleted scenes", %{user: user, project: project} do
      other = project_fixture(user)
      other_scene = scene_fixture(other, %{name: "Elsewhere"})

      deleted = scene_fixture(project, %{name: "Deleted"})
      {:ok, _} = Scenes.delete_scene(deleted)

      scene_ids = project.id |> Scenes.list_dashboard_health_findings() |> MapSet.new(& &1.scene_id)

      refute MapSet.member?(scene_ids, other_scene.id)
      refute MapSet.member?(scene_ids, deleted.id)
    end
  end

  describe "editor and dashboard agree" do
    test "on every scene of the project", %{project: project, world: world} do
      dashboard = Scenes.list_dashboard_health_findings(project.id)

      for scene <- world.scenes do
        assert editor_tuples(project, scene) == dashboard_tuples(dashboard, scene.id),
               "editor and dashboard disagree about scene #{scene.name} (##{scene.id})"
      end
    end

    test "on a scene whose findings all come from reference integrity", %{project: project, world: world} do
      # This is the family the dashboard has to load project references for. If
      # `references_loaded` were left false, all of these would silently vanish
      # from the dashboard while the editor kept showing them.
      dashboard = dashboard_tuples(Scenes.list_dashboard_health_findings(project.id), world.pins.id)

      assert {"error", "stale_pin_sheet_reference", "pin", world.stale_sheet_pin_id} in dashboard
      assert editor_tuples(project, world.pins) == dashboard
    end
  end

  describe "the vocabulary is single-sourced" do
    test "every code the checker can emit has a declared severity" do
      for code <- HealthChecker.codes() do
        assert HealthChecker.severity_for(code) in [:error, :warning, :info]
      end
    end

    test "an unknown code raises instead of defaulting to a severity" do
      assert_raise KeyError, fn -> HealthChecker.severity_for(:not_a_real_code) end
    end
  end

  # ===========================================================================
  # Surface adapters
  # ===========================================================================

  # Drives the REAL editor entry point: the socket assigns `SceneLive.Show`
  # builds, through `HealthHelpers.assign_scene_health/1`.
  defp editor_tuples(project, scene) do
    scene = Scenes.get_scene(project.id, scene.id)

    %Phoenix.LiveView.Socket{}
    |> Phoenix.Component.assign(:scene, scene)
    |> Phoenix.Component.assign(:layers, scene.layers)
    |> Phoenix.Component.assign(:zones, scene.zones)
    |> Phoenix.Component.assign(:pins, scene.pins)
    |> Phoenix.Component.assign(:connections, scene.connections)
    |> Phoenix.Component.assign(:annotations, scene.annotations)
    |> Phoenix.Component.assign(:ambient_flows, Scenes.list_ambient_flows(scene.id))
    |> Phoenix.Component.assign(:health_references_loaded, true)
    |> Phoenix.Component.assign(:project_scenes, Scenes.list_scenes(project.id))
    |> Phoenix.Component.assign(:project_sheets, Storyarn.Sheets.list_sheets_tree(project.id))
    |> Phoenix.Component.assign(:project_flows, Storyarn.Flows.list_flows(project.id))
    |> Phoenix.Component.assign(:project_variables, VariableHelpers.list_all_variables(project.id))
    |> Phoenix.Component.assign(:project_asset_ids, Assets.list_asset_ids(project.id, images_only: true))
    |> HealthHelpers.assign_scene_health()
    |> then(& &1.assigns.scene_health)
    |> payload_tuples()
  end

  defp payload_tuples(payload) do
    for_result =
      for {severity, key} <- [{"error", :errorItems}, {"warning", :warningItems}, {"info", :infoItems}],
          item <- Map.fetch!(payload, key),
          reason <- item.reasons do
        {severity, reason.code, item.entityType, item.entityId}
      end

    Enum.sort(for_result)
  end

  defp dashboard_tuples(findings, scene_id) do
    findings
    |> Enum.filter(&(&1.scene_id == scene_id))
    |> Enum.map(&{to_string(&1.severity), to_string(&1.code), &1.entity_type, &1.entity_id})
    |> Enum.sort()
  end

  # ===========================================================================
  # The world: one scene per code family
  # ===========================================================================

  defp build_world(user, project) do
    sheet = sheet_fixture(project, %{name: "Hero", shortcut: "hero"})
    block_fixture(sheet, %{type: "number", config: %{"label" => "Health"}})

    gone_sheet = sheet_fixture(project, %{name: "Ghost"})
    {:ok, _} = Storyarn.Sheets.delete_sheet(gone_sheet)

    gone_flow = deleted_flow_fixture(project, "Gone Flow")
    also_gone_flow = deleted_flow_fixture(project, "Also Gone Flow")
    live_flow = flow_fixture(project, %{name: "Live Flow"})
    other_live_flow = flow_fixture(project, %{name: "Other Live Flow"})

    image = image_asset_fixture(project, user)
    # An asset that exists but is not in the project's IMAGE set: exactly what a
    # reference to a deleted-then-replaced background looks like to the checker.
    non_image = asset_fixture(project, user, %{content_type: "application/pdf"})

    refs = %{
      sheet: sheet,
      gone_sheet: gone_sheet,
      gone_flow: gone_flow,
      also_gone_flow: also_gone_flow,
      live_flow: live_flow,
      other_live_flow: other_live_flow,
      image: image,
      non_image: non_image
    }

    empty = build_empty_scene(project)
    layers = build_layer_scene(project, refs)
    no_default = build_no_default_layer_scene(project)
    zones = build_zone_scene(project, refs)
    {pins, stale_sheet_pin_id} = build_pin_scene(project, refs)
    leader = build_leader_scene(project)
    routes = build_route_scene(project)
    ambient = build_ambient_scene(project, refs)

    %{
      scenes: [empty, layers, no_default, zones, pins, leader, routes, ambient],
      pins: pins,
      stale_sheet_pin_id: stale_sheet_pin_id
    }
  end

  # missing_scene_layer, missing_scene_shortcut, missing_background, empty_scene
  defp build_empty_scene(project) do
    scene = scene_fixture(project, %{name: "Bare"})
    Repo.delete_all(from(l in SceneLayer, where: l.scene_id == ^scene.id))
    update_scene(scene, shortcut: nil, background_asset_id: nil)
  end

  # multiple_default_layers, invalid_asset_reference
  defp build_layer_scene(project, refs) do
    scene = scene_fixture(project, %{name: "Two Defaults"})
    Repo.update_all(from(l in SceneLayer, where: l.scene_id == ^scene.id), set: [is_default: true])
    insert_layers(scene, [%{name: "Also Default", is_default: true}])
    insert_pins(scene, [%{label: "Anyone", is_playable: false}])
    update_scene(scene, background_asset_id: refs.non_image.id)
  end

  # missing_default_layer
  defp build_no_default_layer_scene(project) do
    scene = scene_fixture(project, %{name: "No Default"})
    Repo.update_all(from(l in SceneLayer, where: l.scene_id == ^scene.id), set: [is_default: false])
    insert_pins(scene, [%{label: "Anyone"}])
    with_background(scene)
  end

  # Every zone-side code, plus the condition and assignment families.
  defp build_zone_scene(project, refs) do
    scene = scene_fixture(project, %{name: "Zones"})
    foreign_layer_id = foreign_layer_id(project, scene)

    insert_zones(scene, [
      %{name: "Broken Geometry", vertices: [point(0)]},
      %{name: "Off Canvas", vertices: [point(0), point(10), point(150)]},
      %{name: "Icon Label", label_mode: "icon"},
      %{name: "Display No Label", action_type: "display", label_mode: "none", action_data: display("hero.health")},
      %{name: "Foreign Layer", layer_id: foreign_layer_id},
      %{name: "Empty Action", action_type: "action", action_data: %{"assignments" => []}},
      %{
        name: "Stale Target",
        action_type: "action",
        action_data: %{"assignments" => []},
        target_type: "flow",
        target_id: refs.gone_flow.id
      },
      %{name: "No Display Var", action_type: "display", action_data: display("")},
      %{name: "Stale Display Var", action_type: "display", action_data: display("hero.nope")},
      %{name: "Empty Collection", action_type: "collection", action_data: %{"items" => []}},
      %{name: "Broken Item", action_type: "collection", action_data: %{"items" => [%{"id" => "nope"}]}},
      %{name: "Stale Item Sheet", action_type: "collection", action_data: collection(refs.gone_sheet.id)},
      %{name: "Incomplete Assignment", action_type: "action", action_data: assignments("")},
      %{name: "Mistyped Assignment", action_type: "action", action_data: assignments("1", "contains")},
      %{name: "Broken Condition", condition: %{"logic" => "nope", "blocks" => []}},
      %{name: "Empty Condition", condition: %{"logic" => "all", "blocks" => []}},
      %{name: "Incomplete Condition", condition: condition(nil, nil, "equals", nil)},
      # Pin and zone shortcuts are variables too. A surface that only loaded
      # SHEET variables would call both of these references stale.
      %{name: "Gate", shortcut: "gate"},
      %{name: "Shows Pin Property", action_type: "display", action_data: display("guard.hidden")},
      %{name: "Shows Zone Property", action_type: "display", action_data: display("gate.hidden")}
    ])

    with_background(scene)
  end

  # Every pin-side code, including the patrol family.
  defp build_pin_scene(project, refs) do
    scene = scene_fixture(project, %{name: "Pins"})
    foreign_layer_id = foreign_layer_id(project, scene)

    [_off, stale_sheet, _stale_flow, _bad_icon, _foreign, _playable, _patrol_playable, _lonely, branch, a, b, _guard] =
      insert_pins(scene, [
        %{label: "Off Canvas", position_x: 150.0},
        %{label: "Stale Sheet Pin", sheet_id: refs.gone_sheet.id},
        %{label: "Stale Flow Pin", flow_id: refs.gone_flow.id},
        %{label: "Bad Icon", icon_asset_id: refs.non_image.id},
        %{label: "Foreign Layer", layer_id: foreign_layer_id},
        %{label: "Playable", is_playable: true},
        %{label: "Patrolling Player", is_playable: true, patrol_mode: "loop"},
        %{label: "Lonely Patrol", patrol_mode: "loop"},
        %{label: "Branch Patrol", patrol_mode: "loop"},
        %{label: "Fork A"},
        %{label: "Fork B"},
        %{label: "Guard", shortcut: "guard"}
      ])

    insert_connections(scene, [
      %{label: "Fork 1", from_pin_id: branch.id, to_pin_id: a.id},
      %{label: "Fork 2", from_pin_id: branch.id, to_pin_id: b.id}
    ])

    {with_background(scene), stale_sheet.id}
  end

  # leader_without_walkable_area
  defp build_leader_scene(project) do
    scene = scene_fixture(project, %{name: "Leader"})
    insert_pins(scene, [%{label: "Captain", is_playable: true, is_leader: true}])
    with_background(scene)
  end

  # The connection family, plus an annotation to prove annotations are loaded.
  defp build_route_scene(project) do
    scene = scene_fixture(project, %{name: "Routes"})
    [from, to] = insert_pins(scene, [%{label: "Start"}, %{label: "End"}])

    insert_connections(scene, [
      %{label: "Bad Pause", from_pin_id: from.id, to_pin_id: to.id, from_pause_ms: -1},
      %{label: "Self Loop", from_pin_id: from.id, to_pin_id: from.id},
      %{label: "Off Canvas Route", from_pin_id: from.id, to_pin_id: to.id, waypoints: [point(150)]}
    ])

    insert_annotations(scene, [%{text: "Way Out", position_x: 150.0}])
    with_background(scene)
  end

  # The ambient flow family.
  defp build_ambient_scene(project, refs) do
    scene = scene_fixture(project, %{name: "Ambient"})
    insert_pins(scene, [%{label: "Anyone"}])

    insert_ambient_flows(scene, [
      %{flow_id: refs.live_flow.id, trigger_type: "timed", trigger_config: %{"interval_ms" => 100}},
      %{flow_id: refs.other_live_flow.id, trigger_type: "on_event", trigger_config: %{"variable_ref" => ""}},
      %{flow_id: refs.gone_flow.id},
      # Disabled rows must stay silent on BOTH surfaces.
      %{flow_id: refs.also_gone_flow.id, enabled: false}
    ])

    with_background(scene)
  end

  # ===========================================================================
  # Raw writers
  #
  # These fabricate persisted state the current changesets would refuse. That is
  # the point: the checker's job is to interpret rows that are already in the
  # database, whatever wrote them.
  # ===========================================================================

  defp insert_layers(scene, rows), do: insert_rows("scene_layers", scene, rows, %{})

  defp insert_zones(scene, rows) do
    # `is_walkable` and `action_type` are one fact in two columns — the checker
    # reports a disagreement as `invalid_zone_action_configuration`, so derive it
    # unless a case is deliberately about that disagreement.
    rows =
      Enum.map(rows, fn row ->
        Map.put_new(row, :is_walkable, Map.get(row, :action_type, "walkable") == "walkable")
      end)

    insert_rows("scene_zones", scene, rows, %{
      vertices: [point(0), point(10), %{"x" => 0, "y" => 10}],
      layer_id: default_layer_id(scene),
      action_type: "walkable",
      action_data: %{},
      label_mode: "text"
    })
  end

  defp insert_pins(scene, rows) do
    insert_rows("scene_pins", scene, rows, %{
      position_x: 50.0,
      position_y: 50.0,
      layer_id: default_layer_id(scene)
    })
  end

  defp insert_connections(scene, rows), do: insert_rows("scene_connections", scene, rows, %{waypoints: []})

  defp insert_annotations(scene, rows) do
    insert_rows("scene_annotations", scene, rows, %{
      position_x: 50.0,
      position_y: 50.0,
      layer_id: default_layer_id(scene)
    })
  end

  defp insert_ambient_flows(scene, rows) do
    insert_rows("scene_ambient_flows", scene, rows, %{trigger_type: "on_enter", trigger_config: %{}})
  end

  # `scene_connections` is the one child table without a `position` column.
  @positioned_tables ~w(scene_layers scene_zones scene_pins scene_annotations scene_ambient_flows)

  defp insert_rows(table, scene, rows, defaults) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    entries =
      rows
      |> Enum.with_index(1)
      |> Enum.map(fn {row, index} ->
        defaults
        |> Map.merge(row)
        |> Map.merge(%{scene_id: scene.id, inserted_at: now, updated_at: now})
        |> then(&if table in @positioned_tables, do: Map.put(&1, :position, index), else: &1)
      end)

    {_count, inserted} = Repo.insert_all(table, entries, returning: [:id])
    inserted
  end

  defp default_layer_id(scene) do
    Repo.one(from(l in SceneLayer, where: l.scene_id == ^scene.id, order_by: [asc: l.position], limit: 1, select: l.id))
  end

  defp foreign_layer_id(project, scene) do
    other = scene_fixture(project, %{name: "Donor for #{scene.name}"})
    # The donor scene needs content of its own or it reports `empty_scene`, which
    # is fine — every scene of the project goes through the agreement test.
    insert_pins(other, [%{label: "Resident"}])
    with_background(other)
    default_layer_id(other)
  end

  defp deleted_flow_fixture(project, name) do
    flow = flow_fixture(project, %{name: name})
    {:ok, _} = Storyarn.Flows.delete_flow(flow)
    flow
  end

  defp update_scene(scene, changes) do
    {1, _} = Repo.update_all(from(s in Scene, where: s.id == ^scene.id), set: changes)
    Repo.reload!(scene)
  end

  defp with_background(scene) do
    update_scene(scene, background_asset_id: background_asset_id(scene.project_id))
  end

  # One shared image for every scene that should NOT report `missing_background`.
  defp background_asset_id(project_id) do
    case Assets.list_asset_ids(project_id, images_only: true) do
      [id | _] -> id
      [] -> nil
    end
  end

  # ===========================================================================
  # Value builders
  # ===========================================================================

  defp point(value), do: %{"x" => value, "y" => value}

  defp display(ref), do: %{"variable_ref" => ref, "display_mode" => "value"}

  defp collection(sheet_id) do
    %{
      "items" => [
        %{"id" => @item_id, "label" => "Ghost Item", "sheet_id" => sheet_id, "condition" => nil}
      ]
    }
  end

  defp assignments(value, operator \\ "add") do
    %{
      "assignments" => [
        %{"sheet" => "hero", "variable" => "health", "operator" => operator, "value" => value}
      ]
    }
  end

  defp condition(sheet, variable, operator, value) do
    %{
      "logic" => "all",
      "blocks" => [
        %{
          "id" => "block-1",
          "type" => "block",
          "logic" => "all",
          "rules" => [
            %{"id" => "rule-1", "sheet" => sheet, "variable" => variable, "operator" => operator, "value" => value}
          ]
        }
      ]
    }
  end
end
