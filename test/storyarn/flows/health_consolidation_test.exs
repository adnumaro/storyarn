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
  import Storyarn.ScenesFixtures, only: [scene_fixture: 1, pin_fixture: 2]
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Repo

  setup do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  # THE editor's own loader. `Repo.preload([:nodes, :connections])` is not it: the
  # association carries no `deleted_at` filter, so a proxy built on it feeds the
  # composition point a node set the editor never sees and the agreement it pins
  # is an agreement between two things that are both not the product.
  defp editor_findings(flow, project_id) do
    project_id
    |> Flows.get_flow!(flow.id)
    |> Flows.serialize_for_canvas()
    |> Flows.flow_health_findings(project_id)
  end

  defp comparable(findings) do
    findings
    |> Enum.map(&{&1.severity, &1.code, &1.entity_type, &1.entity_id})
    |> Enum.sort()
  end

  defp soft_delete!(node) do
    node |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second)) |> Repo.update!()
  end

  defp severity_rank(:error), do: 0
  defp severity_rank(:warning), do: 1
  defp severity_rank(:info), do: 2

  # The shape `list_referenceable_variables/1` returns, without the database:
  # what is being measured is the keying, not the query.
  defp variable_list(count) do
    for i <- 1..count do
      %{sheet_shortcut: "hero", variable_name: "v#{i}", block_type: "number"}
    end
  end

  # The one keying pass is deliberately OUTSIDE the timer: building the map is
  # O(variables) and always will be. What must not scale is flagging the nodes.
  defp flag_cost(nodes, variables) do
    type_map = Flows.variable_type_map(variables)

    :timer.tc(fn -> Flows.add_health_flags(nodes, MapSet.new(), type_map) end)
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

    test "on the node set itself — a soft-deleted node owns no finding anywhere", %{project: project} do
      flow = flow_fixture(project)
      entry = Enum.find(Flows.list_nodes(flow.id), &(&1.type == "entry"))
      dialogue = node_fixture(flow, %{type: "dialogue", data: %{"text" => ""}})
      connection_fixture(flow, entry, dialogue)

      # Positive control: while the node is active it DOES own findings, so the
      # refutation below cannot pass by the fixture being healthy.
      assert Enum.any?(editor_findings(flow, project.id), &(&1.entity_id == dialogue.id))

      soft_delete!(dialogue)

      editor = editor_findings(flow, project.id)

      refute Enum.any?(editor, &(&1.entity_id == dialogue.id)),
             "the editor loads active nodes only; a deleted node cannot own a finding"

      assert comparable(editor) == comparable(Flows.list_dashboard_health_findings(project.id))
    end

    test "on a sequence node whose row data carries editorial flags", %{project: project} do
      flow = flow_fixture(project)

      # A sequence node is a visual container: `serialize_for_canvas/2` replaces
      # its data with the sequence config alone, so an editorial flag left on the
      # row is invisible to the editor. Reading the row directly is what let the
      # dashboard emit two findings the editor cannot show.
      %FlowNode{flow_id: flow.id}
      |> Ecto.Changeset.change(%{
        type: "sequence",
        data: %{"has_stale_refs" => true, "has_type_warnings" => true},
        position_x: 0.0,
        position_y: 0.0
      })
      |> Repo.insert!()

      assert comparable(editor_findings(flow, project.id)) ==
               comparable(Flows.list_dashboard_health_findings(project.id))
    end
  end

  describe "findings arrive severity-ordered" do
    # The list is rendered in the order it arrives. Composing as
    # `editorial ++ structural` put every `:info` ahead of every `:error`, so on a
    # flow with both, the error sat behind the noise on both surfaces.
    test "the composition point orders errors first", %{project: project} do
      flow = flow_fixture(project)
      entry = Enum.find(Flows.list_nodes(flow.id), &(&1.type == "entry"))
      # No Entry: a flow-level :error. Plus an empty instruction: an :info that
      # the editorial half emits, and that used to be composed in front of it.
      soft_delete!(entry)
      node_fixture(flow, %{type: "instruction", data: %{"assignments" => []}})

      findings = editor_findings(flow, project.id)
      severities = Enum.map(findings, & &1.severity)

      # Positive control: the fixture really does span both ends of the catalog.
      assert :error in severities
      assert :info in severities

      assert severities == Enum.sort_by(severities, &severity_rank/1)
      assert List.first(severities) == :error
    end
  end

  describe "health flagging does not scale with the variable set" do
    # `has_type_warnings?/2` used to key the project type map on EVERY call —
    # once per instruction node and once per dialogue response. Measured at 200
    # flows / 4000 variables: 1599 ms of a 1666 ms sweep, 96% of it, and a 15×
    # penalty on every flow open.
    #
    # This times `add_health_flags/3` rather than the whole sweep: at the sweep
    # level the fixed DB cost of a test-sized project drowns the signal, and an
    # absolute budget would be flaky anyway (the same call measured 12.6 ms and
    # 39.4 ms under different load). What is asserted is the RATIO between two
    # variable-set sizes over an identical node list — the shape of the bug.
    test "flagging 200 nodes costs the same at 10 variables as at 4000" do
      nodes =
        for id <- 1..200 do
          %{
            id: id,
            type: "instruction",
            data: %{
              "assignments" => [
                # `append` is not an operator a number accepts, so the check runs
                # to a real verdict instead of short-circuiting on a miss.
                %{"sheet" => "hero", "variable" => "v1", "operator" => "append", "value" => "1"}
              ]
            }
          }
        end

      small = variable_list(10)
      large = variable_list(4000)

      # Warm the code path so the ratio measures the work, not first-call setup.
      flag_cost(nodes, small)
      flag_cost(nodes, large)

      {small_us, small_flagged} = flag_cost(nodes, small)
      {large_us, large_flagged} = flag_cost(nodes, large)

      # Positive control: the flag really is being computed on both sides, so a
      # flat ratio cannot come from the check being skipped.
      assert Enum.all?(small_flagged, & &1.data["has_type_warnings"])
      assert Enum.all?(large_flagged, & &1.data["has_type_warnings"])

      ratio = large_us / max(small_us, 1)

      # Measured: ~700× rebuilding the map per node, ~5.5× without. It is not 1×
      # because a 4000-key hashmap lookup is genuinely dearer than a 10-key
      # flatmap one — that residue is the cost of the data, not of rebuilding it.
      # 50 leaves ~14× of headroom on both sides.
      assert ratio < 50,
             "flagging cost scales with the variable set: #{Float.round(ratio, 1)}× " <>
               "(#{small_us}µs at 10 variables vs #{large_us}µs at 4000)"
    end

    test "the type check refuses the variable list, so a per-node rebuild cannot be written" do
      variables = variable_list(3)
      assignments = [%{"sheet" => "hero", "variable" => "v1", "operator" => "append", "value" => "1"}]

      # The prepared map is the contract.
      assert Flows.instruction_has_type_warnings?(assignments, Flows.variable_type_map(variables))

      # Handing it the list instead — which is what every call site used to do,
      # once per node — must not silently answer `false`.
      assert_raise FunctionClauseError, fn ->
        Flows.instruction_has_type_warnings?(assignments, variables)
      end
    end
  end

  describe "the sweep order does not depend on the query plan" do
    # The project-wide node query carried no `order_by` at all, so Postgres
    # returned whatever the plan produced. Proven on the dev DB: a seqscan and an
    # index scan give different node order with zero position ties, which moves
    # the dashboard's rows under the reader.
    test "an UPDATE plus a different query plan does not reorder the findings", %{project: project} do
      flow = flow_fixture(project, %{name: "Twenty"})

      nodes =
        for _ <- 1..20 do
          node_fixture(flow, %{type: "dialogue", data: %{"text" => ""}})
        end

      before = Flows.list_dashboard_health_findings(project.id)
      assert length(before) > 20, "fixture must produce enough rows for order to be observable"

      # An UPDATE writes a new heap tuple at the end of the relation, so it moves
      # the row under a seqscan but not under an index scan. On a test-sized
      # table Postgres always picks the index on `flow_id`; on a real one it does
      # not, which is how this was proven unstable against `storyarn_dev`.
      # Forcing the plan is what makes that difference observable here.
      nodes |> Enum.at(7) |> Ecto.Changeset.change(%{position_x: 42.0}) |> Repo.update!()
      Repo.query!("SET LOCAL enable_indexscan = off")
      Repo.query!("SET LOCAL enable_bitmapscan = off")

      after_update = Flows.list_dashboard_health_findings(project.id)

      assert Enum.map(before, &{&1.severity, &1.code, &1.entity_id}) ==
               Enum.map(after_update, &{&1.severity, &1.code, &1.entity_id})
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
      %FlowNode{flow_id: flow.id}
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
