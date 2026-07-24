defmodule Storyarn.Flows.StructuralAnalysis.Rules do
  @moduledoc """
  Frozen v1 catalog of structural-analysis rules.

  Every rule declares its contract: semantic version, curated category and
  severity, target type, and what its evidence contains. Categories and
  severities are product metadata — never caller supplied. Rules without
  formal branch/cycle/span semantics (narrative quality, condition
  satisfiability) are out of scope by design.

  Rule ids reuse the existing `Flows.HealthChecker` codes where the concept
  already exists; `isolated_node` and `orphan_hub` are new canonical rules.
  """

  @type category :: :structure | :reference_integrity
  @type severity :: :error | :warning
  @type rule :: %{
          version: pos_integer(),
          category: category(),
          severity: severity(),
          target: :flow | :node,
          evidence: [atom()],
          inputs: [atom()],
          limitations_key: String.t()
        }

  # Shared canonical-input sets. `:graph` = active nodes/types, stored
  # connections, resolved jump virtual edges, and per-node output pin sets
  # (the graph_digest contract in StructuralAnalysis).
  @graph_inputs [:graph]
  @node_data_inputs [:node_data]

  @rules %{
    "missing_entry" => %{
      version: 1,
      category: :structure,
      severity: :error,
      target: :flow,
      evidence: [:flow],
      inputs: @graph_inputs,
      limitations_key: "flows.analysis.limitations.missing_entry"
    },
    "multiple_entries" => %{
      version: 1,
      category: :structure,
      severity: :error,
      target: :flow,
      evidence: [:flow, :entry_nodes],
      inputs: @graph_inputs,
      limitations_key: "flows.analysis.limitations.multiple_entries"
    },
    "unreachable_node" => %{
      version: 1,
      category: :structure,
      severity: :warning,
      target: :node,
      evidence: [:node],
      inputs: @graph_inputs,
      limitations_key: "flows.analysis.limitations.unreachable_node"
    },
    "isolated_node" => %{
      version: 1,
      category: :structure,
      severity: :warning,
      target: :node,
      evidence: [:node],
      inputs: @graph_inputs,
      limitations_key: "flows.analysis.limitations.isolated_node"
    },
    "no_outgoing_connection" => %{
      version: 1,
      category: :structure,
      severity: :warning,
      target: :node,
      evidence: [:node],
      inputs: @graph_inputs,
      limitations_key: "flows.analysis.limitations.no_outgoing_connection"
    },
    "missing_output_connections" => %{
      version: 1,
      category: :structure,
      severity: :warning,
      target: :node,
      evidence: [:node],
      inputs: @graph_inputs,
      limitations_key: "flows.analysis.limitations.missing_output_connections"
    },
    "invalid_output_pins" => %{
      version: 1,
      category: :structure,
      severity: :error,
      target: :node,
      evidence: [:node, :connections],
      inputs: @graph_inputs,
      limitations_key: "flows.analysis.limitations.invalid_output_pins"
    },
    "invalid_input_pins" => %{
      version: 1,
      category: :structure,
      severity: :error,
      target: :node,
      evidence: [:node, :connections],
      inputs: @graph_inputs,
      limitations_key: "flows.analysis.limitations.invalid_input_pins"
    },
    "orphan_hub" => %{
      version: 1,
      category: :structure,
      severity: :warning,
      target: :node,
      evidence: [:node],
      inputs: @graph_inputs,
      limitations_key: "flows.analysis.limitations.orphan_hub"
    },
    "missing_jump_target" => %{
      version: 1,
      category: :reference_integrity,
      severity: :error,
      target: :node,
      evidence: [:node],
      inputs: @node_data_inputs,
      limitations_key: "flows.analysis.limitations.missing_jump_target"
    },
    "stale_jump_target" => %{
      version: 1,
      category: :reference_integrity,
      severity: :error,
      target: :node,
      evidence: [:node],
      inputs: @node_data_inputs,
      limitations_key: "flows.analysis.limitations.stale_jump_target"
    },
    "missing_subflow_reference" => %{
      version: 1,
      category: :reference_integrity,
      severity: :error,
      target: :node,
      evidence: [:node],
      inputs: @node_data_inputs,
      limitations_key: "flows.analysis.limitations.missing_subflow_reference"
    },
    "stale_subflow_reference" => %{
      version: 1,
      category: :reference_integrity,
      severity: :error,
      target: :node,
      evidence: [:node],
      inputs: @node_data_inputs,
      limitations_key: "flows.analysis.limitations.stale_subflow_reference"
    },
    "missing_exit_flow_reference" => %{
      version: 1,
      category: :reference_integrity,
      severity: :error,
      target: :node,
      evidence: [:node],
      inputs: @node_data_inputs,
      limitations_key: "flows.analysis.limitations.missing_exit_flow_reference"
    },
    "stale_exit_flow_reference" => %{
      version: 1,
      category: :reference_integrity,
      severity: :error,
      target: :node,
      evidence: [:node],
      inputs: @node_data_inputs,
      limitations_key: "flows.analysis.limitations.stale_exit_flow_reference"
    }
  }

  @rule_ids Map.keys(@rules)

  @spec all() :: %{String.t() => rule()}
  def all, do: @rules

  @spec rule_ids() :: [String.t()]
  def rule_ids, do: @rule_ids

  @spec fetch!(String.t()) :: rule()
  def fetch!(rule_id), do: Map.fetch!(@rules, rule_id)

  @spec known?(String.t()) :: boolean()
  def known?(rule_id), do: Map.has_key?(@rules, rule_id)
end
