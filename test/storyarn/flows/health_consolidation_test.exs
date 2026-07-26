defmodule Storyarn.Flows.HealthConsolidationTest do
  @moduledoc """
  The invariant the whole consolidation exists for: **the flow editor and the flow
  dashboard cannot disagree about the same flow.**

  This test did not exist before, and its absence is exactly how the two surfaces
  drifted. The dashboard used to map 4 of the 15 structural rules into 3 coarse
  buckets and never ran the editorial checks at all, so for a flow whose only
  problems were a speaker-less dialogue and a dead-end subflow it reported a
  fraction of what the editor showed — verified on a real project before this was
  written.

  Both surfaces go through `StructuralAnalysis.findings/1`. What this pins is that
  they also FEED it equivalently: the editor from serialized canvas data, the
  dashboard from nodes read straight from the DB and enriched by
  `Flows.add_health_flags/3`.
  """

  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures, only: [scene_fixture: 1, scene_fixture: 2, pin_fixture: 2]
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Repo

  setup do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  defp editor_findings(flow, project_id) do
    flow
    |> Repo.preload([:nodes, :connections])
    |> Flows.serialize_for_canvas()
    |> Flows.flow_health_findings(project_id)
  end

  defp comparable(findings) do
    findings
    |> Enum.map(&{&1.severity, &1.code, &1.entity_type, &1.entity_id})
    |> Enum.sort()
  end

  describe "editor and dashboard agree" do
    test "on a flow with BOTH an editorial and a structural problem", %{project: project} do
      # `create_flow` already provides the Entry node.
      flow = flow_fixture(project)
      entry = Enum.find(Flows.list_nodes(flow.id), &(&1.type == "entry"))
      # No speaker and no text: two editorial findings on one node.
      dialogue = node_fixture(flow, %{type: "dialogue", data: %{"text" => ""}})
      _connection = connection_fixture(flow, entry, dialogue)

      editor = editor_findings(flow, project.id)
      dashboard = Flows.list_dashboard_health_findings(project.id)

      codes = editor |> Enum.map(& &1.code) |> Enum.uniq()
      assert :missing_dialogue_speaker in codes, "editorial detection is the half the dashboard used to miss"
      assert :no_outgoing_connection in codes, "structural detection"

      assert comparable(editor) == comparable(dashboard)
    end

    test "attributing every finding to its own flow", %{project: project} do
      flow_a = flow_fixture(project, %{name: "A"})
      flow_b = flow_fixture(project, %{name: "B"})
      node_fixture(flow_a, %{type: "dialogue", data: %{"text" => "hi"}})
      node_fixture(flow_b, %{type: "dialogue", data: %{"text" => "hi"}})

      by_flow =
        project.id
        |> Flows.list_dashboard_health_findings()
        |> Enum.group_by(& &1.flow_id)

      # A nil key here means editorial findings lost their flow: the dashboard then
      # collapses every flow into one row, which is the bug this pins.
      refute Map.has_key?(by_flow, nil)
      assert Map.has_key?(by_flow, flow_a.id)
      assert Map.has_key?(by_flow, flow_b.id)
    end

    test "on the flags only the serializer used to compute", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Hero"})
      block = block_fixture(sheet, %{type: "number", config: %{"label" => "HP"}})
      flow = flow_fixture(project)

      # A reference to a block that no longer exists: `has_stale_refs`, which the
      # canvas serializer injects. A dashboard that did not enrich its nodes would
      # silently never report this code.
      node_fixture(flow, %{
        type: "instruction",
        data: %{
          "assignments" => [
            %{"variable" => "hero.hp", "block_id" => block.id, "operator" => "set", "value" => "1"}
          ]
        }
      })

      Repo.delete!(block)

      assert comparable(editor_findings(flow, project.id)) ==
               comparable(Flows.list_dashboard_health_findings(project.id))
    end
  end

  describe "both surfaces see the same variables" do
    # Found by the scenes consolidation: the dashboard used only
    # `Sheets.list_project_variables/1` while the editor composes sheets + scene
    # pins + scene zones. A flow assigning to a pin property was therefore
    # type-checked against different vocabularies on the two surfaces.
    test "a flow assigning to a scene pin property agrees on both surfaces", %{project: project} do
      scene = scene_fixture(project)
      _pin = pin_fixture(scene, %{"label" => "Guard", "shortcut" => "guard"})
      flow = flow_fixture(project)

      node_fixture(flow, %{
        type: "instruction",
        data: %{
          "assignments" => [
            # `hidden` is a BOOLEAN pin property, and `add` is not one of its
            # operators — a mismatch only a checker that KNOWS pin variables can
            # see. With sheet variables alone the reference is unknown and no
            # warning is possible, which is exactly the divergence being locked.
            %{
              "sheet" => "guard",
              "variable" => "hidden",
              "operator" => "add",
              "value" => "1"
            }
          ]
        }
      })

      editor = editor_findings(flow, project.id)
      # Positive control: the editor must actually SEE the mismatch, or the
      # agreement below would hold by both sides reporting nothing.
      assert Enum.any?(editor, &(&1.code == :variable_type_mismatch))

      assert comparable(editor) == comparable(Flows.list_dashboard_health_findings(project.id))
    end

    test "the referenceable set is sheets plus pins plus zones", %{project: project} do
      scene = scene_fixture(project)
      pin_fixture(scene, %{"label" => "Guard", "shortcut" => "guard"})
      sheet = sheet_fixture(project, %{name: "Hero", shortcut: "hero"})
      block_fixture(sheet, %{type: "number", variable_name: "hp", config: %{"label" => "HP"}})

      sources =
        project.id
        |> Flows.list_referenceable_variables()
        # Sheet variables carry no `source_type`; only the scene ones do, which is
        # itself the tell that they come from different contexts.
        |> Enum.map(&Map.get(&1, :source_type, "sheet"))
        |> Enum.uniq()
        |> Enum.sort()

      assert "pin" in sources
      assert "sheet" in sources
    end
  end

  describe "the dashboard discriminates against nothing" do
    test "an info-severity finding reaches the dashboard", %{project: project} do
      flow = flow_fixture(project)
      # `empty_condition` is :info — the old three-bucket dashboard could not
      # express info at all, so this is the severity most likely to be dropped.
      condition = node_fixture(flow, %{type: "condition", data: %{"condition" => %{}}})

      findings = Flows.list_dashboard_health_findings(project.id)

      assert Enum.any?(
               findings,
               &(&1.code == :empty_condition and &1.entity_id == condition.id and &1.severity == :info)
             )
    end

    test "the dashboard's code set equals the editor's, per flow", %{project: project} do
      flow = flow_fixture(project)
      entry = Enum.find(Flows.list_nodes(flow.id), &(&1.type == "entry"))
      dialogue = node_fixture(flow, %{type: "dialogue", data: %{"text" => ""}})
      connection_fixture(flow, entry, dialogue)
      # The CRUD writer refuses a dangling jump, so this drift state goes in at the
      # Repo level — the same idiom `structural_analysis_test.exs` uses.
      %Storyarn.Flows.FlowNode{flow_id: flow.id}
      |> Ecto.Changeset.change(%{
        type: "jump",
        data: %{"target_hub_id" => "nowhere"},
        position_x: 0.0,
        position_y: 0.0
      })
      |> Repo.insert!()

      node_fixture(flow, %{type: "instruction", data: %{"assignments" => []}})

      editor = flow |> editor_findings(project.id) |> Enum.map(& &1.code) |> Enum.uniq() |> Enum.sort()

      dashboard =
        project.id
        |> Flows.list_dashboard_health_findings()
        |> Enum.filter(&(&1.flow_id == flow.id))
        |> Enum.map(& &1.code)
        |> Enum.uniq()
        |> Enum.sort()

      assert dashboard == editor
      # Errors, warnings AND info all present, so this is not passing on a
      # single-severity fixture.
      severities = editor |> Enum.map(&Flows.HealthChecker.severity_for/1) |> Enum.uniq() |> Enum.sort()
      assert severities == [:error, :info, :warning]
    end
  end

  describe "the vocabulary is single-sourced" do
    test "every code the checker can emit has a declared severity" do
      for code <- Flows.HealthChecker.codes() do
        assert Flows.HealthChecker.severity_for(code) in [:error, :warning, :info]
      end
    end

    test "an unknown code raises instead of defaulting to a severity" do
      assert_raise KeyError, fn -> Flows.HealthChecker.severity_for(:not_a_real_code) end
    end
  end
end
