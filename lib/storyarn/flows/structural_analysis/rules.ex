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
          evidence: [atom()]
        }

  @rules %{
    "missing_entry" => %{
      version: 1,
      category: :structure,
      severity: :error,
      target: :flow,
      evidence: [:flow]
    },
    "multiple_entries" => %{
      version: 1,
      category: :structure,
      severity: :error,
      target: :flow,
      evidence: [:flow, :entry_nodes]
    },
    "unreachable_node" => %{
      version: 1,
      category: :structure,
      severity: :warning,
      target: :node,
      evidence: [:node]
    },
    "isolated_node" => %{
      version: 1,
      category: :structure,
      severity: :warning,
      target: :node,
      evidence: [:node]
    },
    "no_outgoing_connection" => %{
      version: 1,
      category: :structure,
      severity: :warning,
      target: :node,
      evidence: [:node]
    },
    "missing_output_connections" => %{
      version: 1,
      category: :structure,
      severity: :warning,
      target: :node,
      evidence: [:node]
    },
    "invalid_output_pins" => %{
      version: 1,
      category: :structure,
      severity: :error,
      target: :node,
      evidence: [:node, :connections]
    },
    "invalid_input_pins" => %{
      version: 1,
      category: :structure,
      severity: :error,
      target: :node,
      evidence: [:node, :connections]
    },
    "orphan_hub" => %{
      version: 1,
      category: :structure,
      severity: :warning,
      target: :node,
      evidence: [:node]
    },
    "missing_jump_target" => %{
      version: 1,
      category: :reference_integrity,
      severity: :error,
      target: :node,
      evidence: [:node]
    },
    "stale_jump_target" => %{
      version: 1,
      category: :reference_integrity,
      severity: :error,
      target: :node,
      evidence: [:node]
    },
    "missing_subflow_reference" => %{
      version: 1,
      category: :reference_integrity,
      severity: :error,
      target: :node,
      evidence: [:node]
    },
    "stale_subflow_reference" => %{
      version: 1,
      category: :reference_integrity,
      severity: :error,
      target: :node,
      evidence: [:node]
    },
    "missing_exit_flow_reference" => %{
      version: 1,
      category: :reference_integrity,
      severity: :error,
      target: :node,
      evidence: [:node]
    },
    "stale_exit_flow_reference" => %{
      version: 1,
      category: :reference_integrity,
      severity: :error,
      target: :node,
      evidence: [:node]
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
