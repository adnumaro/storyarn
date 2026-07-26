defmodule Storyarn.Exports.ValidatorHealthParityTest do
  @moduledoc """
  The export validator used to reimplement three flow health rules with its own
  raw-connection BFS. It disagreed with the health engine on real flows:

    * **D1** — a flow with disconnected nodes: the validator reported
      `unreachable_nodes` and *no* `orphan_nodes` at all, because its orphan check
      skipped `entry` and `exit`. Health reports `isolated_node` for every one.
    * **D2** — a connection left on a pin the node no longer has: health drops the
      invalid-pin edge and reports `no_outgoing_connection`; the validator counted
      the dead edge as real wiring.
    * **D3** — a correctly wired `entry → jump ⇝ hub → dialogue → exit` flow: the
      validator reported **four false-positive** `unreachable_nodes`, because its
      BFS walked raw connection rows and never resolved the jump→hub virtual edge.
      Health reports none of them.

  Both surfaces now read `Flows.analyze_loaded_flow_structure/1`, so these are
  agreement tests: the validator's structural rules are the health engine's
  findings under the historical `rule:` names.
  """
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Exports.Validator
  alias Storyarn.Flows

  setup do
    %{project: project_fixture(user_fixture())}
  end

  describe "D1 — a flow whose nodes have no connections at all" do
    setup %{project: project} do
      flow = flow_fixture(project, %{name: "D1"})
      lonely_exit = node_fixture(flow, %{type: "exit", data: %{"label" => "End"}})

      %{flow: flow, lonely_exit: lonely_exit}
    end

    test "every disconnected node is reported as an orphan", %{project: project, flow: flow} do
      node_ids = MapSet.new(Flows.list_nodes(flow.id), & &1.id)
      orphans = MapSet.new(rules_with_nodes(project.id, :orphan_nodes))

      assert MapSet.equal?(orphans, node_ids),
             "the entry and exit nodes used to be skipped by the validator's own orphan check"
    end

    test "no node is called unreachable when the flow has no reachable graph at all", %{project: project} do
      assert rules_with_nodes(project.id, :unreachable_nodes) == [],
             "an isolated node is reported once, as isolated — not twice, as isolated and unreachable"
    end

    test "the validator agrees with the health engine node for node", %{project: project} do
      assert structural_rules(project.id) == health_structural_codes(project.id)
    end
  end

  describe "D3 — entry -> jump ~~> hub -> dialogue -> exit" do
    setup %{project: project} do
      flow = flow_fixture(project, %{name: "D3"})
      entry = Enum.find(Flows.list_nodes(flow.id), &(&1.type == "entry"))
      hub = node_fixture(flow, %{type: "hub", data: %{"hub_id" => "H1"}})
      jump = node_fixture(flow, %{type: "jump", data: %{"target_hub_id" => "H1"}})
      dialogue = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hi"}})
      exit_node = node_fixture(flow, %{type: "exit", data: %{"label" => "End"}})

      connection_fixture(flow, entry, jump, %{source_pin: "output", target_pin: "input"})
      connection_fixture(flow, hub, dialogue, %{source_pin: "output", target_pin: "input"})
      connection_fixture(flow, dialogue, exit_node, %{source_pin: "output", target_pin: "input"})

      %{flow: flow, hub: hub, jump: jump, dialogue: dialogue, exit_node: exit_node}
    end

    test "nothing behind the jump is called unreachable", context do
      unreachable = rules_with_nodes(context.project.id, :unreachable_nodes)

      for node <- [context.hub, context.jump, context.dialogue, context.exit_node] do
        refute node.id in unreachable,
               "node #{node.id} is reachable through the jump -> hub virtual edge; " <>
                 "the raw-connection BFS could not see it"
      end
    end

    test "the validator agrees with the health engine node for node", %{project: project} do
      assert structural_rules(project.id) == health_structural_codes(project.id)
    end
  end

  describe "D2 — a connection left on a pin the node no longer has" do
    setup %{project: project} do
      flow = flow_fixture(project, %{name: "D2"})
      entry = Enum.find(Flows.list_nodes(flow.id), &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Hi", "responses" => [%{"id" => "r1", "text" => "Yes"}]}
        })

      exit_node = node_fixture(flow, %{type: "exit", data: %{"label" => "End"}})

      connection_fixture(flow, entry, dialogue, %{source_pin: "output", target_pin: "input"})
      connection_fixture(flow, dialogue, exit_node, %{source_pin: "response_r1", target_pin: "input"})

      # The author deletes response r1. The connection on pin `response_r1`
      # survives in the DB; `response_r1` is no longer an accepted output pin.
      {:ok, _} = Flows.update_node(dialogue, %{data: %{"text" => "Hi", "responses" => []}})

      %{flow: flow, dialogue: dialogue, exit_node: exit_node}
    end

    test "the dead edge stops counting as real wiring", context do
      rules = structural_rules(context.project.id)

      assert {:no_outgoing_connection, context.dialogue.id} in rules,
             "the dialogue's only outgoing edge sits on a pin it no longer has"
    end

    test "the validator agrees with the health engine node for node", %{project: project} do
      assert structural_rules(project.id) == health_structural_codes(project.id)
    end
  end

  describe "what the consolidation does not change" do
    test "a flow with no entry node is still a blocking error", %{project: project} do
      flow = flow_fixture(project, %{name: "No entry"})

      # `Flows.delete_node/1` refuses to remove an entry node
      # (`{:error, :cannot_delete_entry_node}`), so the only way to reach this
      # state is the one that produced it in the field: a row that predates the
      # guard, or one soft-deleted around it.
      flow.id
      |> Flows.list_nodes()
      |> Enum.filter(&(&1.type == "entry"))
      |> Enum.each(&Repo.delete!/1)

      result = Validator.validate_project(project.id)

      assert result.status == :errors
      assert Enum.any?(result.errors, &(&1.rule == :missing_entry and &1.flow_id == flow.id))
    end

    test "newly surfaced structural findings are warnings, so exports are not blocked", %{project: project} do
      flow = flow_fixture(project, %{name: "Disconnected"})
      _lonely = node_fixture(flow, %{type: "exit", data: %{"label" => "End"}})

      result = Validator.validate_project(project.id)

      assert result.status == :warnings
      assert result.errors == []
      assert Enum.any?(result.warnings, &(&1.rule == :orphan_nodes))
    end

    test "every structural finding keeps the export finding shape", %{project: project} do
      flow = flow_fixture(project, %{name: "Shape"})
      _lonely = node_fixture(flow, %{type: "exit", data: %{"label" => "End"}})

      result = Validator.validate_project(project.id)
      orphan = Enum.find(result.warnings, &(&1.rule == :orphan_nodes))

      assert %{level: :warning, rule: :orphan_nodes} = orphan
      assert orphan.flow_id == flow.id
      assert orphan.flow_name == "Shape"
      assert is_integer(orphan.node_id)
      assert is_binary(orphan.node_type)
      assert is_binary(orphan.message)
      assert orphan.message =~ "Shape"
    end
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  # The validator rules that now come out of the health engine, as
  # `{rule_or_code, node_id}` pairs. Reference-integrity and localization rules
  # are excluded: those are still the validator's own checks.
  @structural_rules [:orphan_nodes, :unreachable_nodes, :missing_entry]

  defp structural_rules(project_id) do
    result = Validator.validate_project(project_id)

    (result.errors ++ result.warnings ++ result.info)
    |> Enum.reject(&(&1.rule in non_structural_rules()))
    |> Enum.map(&{export_rule_to_code(&1.rule), Map.get(&1, :node_id)})
    |> Enum.sort()
  end

  defp health_structural_codes(project_id) do
    project_id
    |> Flows.list_dashboard_health_findings()
    |> Enum.reject(&(&1.code in editorial_codes() or &1.code in reference_codes()))
    |> Enum.map(&{&1.code, &1.entity_id})
    |> Enum.sort()
  end

  defp rules_with_nodes(project_id, rule) do
    result = Validator.validate_project(project_id)

    (result.errors ++ result.warnings ++ result.info)
    |> Enum.filter(&(&1.rule == rule))
    |> Enum.map(& &1.node_id)
  end

  # The historical export rule names map back onto the health codes they now carry.
  defp export_rule_to_code(:orphan_nodes), do: :isolated_node
  defp export_rule_to_code(:unreachable_nodes), do: :unreachable_node
  defp export_rule_to_code(rule) when rule in @structural_rules, do: rule
  defp export_rule_to_code(rule), do: rule

  # Not part of the structural comparison: reference integrity, localization and
  # sheet checks are still the validator's own, and `:empty_dialogue` /
  # `:missing_speakers` are the editorial half the export path cannot reach yet.
  defp non_structural_rules do
    [
      :broken_references,
      :empty_dialogue,
      :missing_speakers,
      :missing_translations,
      :orphan_sheets,
      :preview_localization
    ]
  end

  # Editorial findings do not reach the export path: `analyze_loaded_flow_structure/1`
  # is the structural half only.
  defp editorial_codes do
    [
      :empty_condition,
      :empty_dialogue_response,
      :empty_instruction,
      :incomplete_condition,
      :incomplete_instruction_assignment,
      :incomplete_response_assignment,
      :incomplete_response_condition,
      :missing_dialogue_speaker,
      :missing_dialogue_text,
      :response_type_mismatch,
      :stale_variable_reference,
      :variable_type_mismatch
    ]
  end

  # Already reported by the validator's own `check_broken_references/2`, at :error.
  defp reference_codes do
    [:missing_jump_target, :stale_jump_target, :missing_subflow_reference, :stale_subflow_reference]
  end
end
