defmodule Storyarn.Flows.StructuralAnalysis.Finding do
  @moduledoc """
  Canonical structural finding contract.

  Identity:

  - `finding_key` — stable identity for rule + flow + target, independent of
    localized copy and of the evidence details.
  - `evidence_fingerprint` — SHA-256 over the canonical rule inputs needed to
    reproduce this occurrence. Negative graph claims (reachability family)
    include the relevant topology digest.
  - `finding_id` — versioned opaque id derived from the finding identity and
    the evidence fingerprint. A changed rule version or changed evidence
    yields a different id.

  Evidence descriptors carry ids only (`%{type, id}`), never caller-authored
  content. Types are the project-owned types supported by the Slice-6 context
  boundary (`flow`, `flow_node`, `flow_connection`).
  """

  alias Storyarn.Flows.StructuralAnalysis.Rules
  alias Storyarn.Shared.CanonicalJSON

  @id_scheme "sf1"

  @enforce_keys [:rule_id, :rule_version, :category, :severity, :flow_id, :target]
  defstruct [
    :rule_id,
    :rule_version,
    :category,
    :severity,
    :flow_id,
    :target,
    :finding_key,
    :evidence_fingerprint,
    :finding_id,
    details: %{},
    evidence: []
  ]

  @type target :: %{type: :flow | :node, id: integer()}
  @type evidence_item :: %{type: String.t(), id: integer()}
  @type t :: %__MODULE__{}

  @doc """
  Builds a finding for `rule_id` with computed identity fields.

  `fingerprint_inputs` must contain every canonical input the rule used to
  reach its conclusion; it is hashed, never stored or exposed.
  """
  @spec build(String.t(), pos_integer(), target(), keyword()) :: t()
  def build(rule_id, flow_id, target, opts) do
    rule = Rules.fetch!(rule_id)
    details = Keyword.get(opts, :details, %{})
    evidence = Keyword.get(opts, :evidence, [])
    fingerprint_inputs = Keyword.fetch!(opts, :fingerprint_inputs)

    finding_key = "#{rule_id}:#{flow_id}:#{target.type}:#{target.id}"

    evidence_fingerprint =
      CanonicalJSON.hash!(%{
        "rule_id" => rule_id,
        "rule_version" => rule.version,
        "inputs" => fingerprint_inputs
      })

    finding_id =
      "#{@id_scheme}_" <>
        CanonicalJSON.hash!(%{
          "key" => finding_key,
          "rule_version" => rule.version,
          "fingerprint" => evidence_fingerprint
        })

    %__MODULE__{
      rule_id: rule_id,
      rule_version: rule.version,
      category: rule.category,
      severity: rule.severity,
      flow_id: flow_id,
      target: target,
      details: details,
      evidence: evidence,
      finding_key: finding_key,
      evidence_fingerprint: evidence_fingerprint,
      finding_id: finding_id
    }
  end

  @category_order %{structure: 0, reference_integrity: 1}
  @severity_order %{error: 0, warning: 1}

  @doc """
  Deterministic total order, independent of discovery/query order:
  category → severity → rule id → target → key.
  """
  @spec sort([t()]) :: [t()]
  def sort(findings) do
    Enum.sort_by(findings, fn f ->
      {Map.fetch!(@category_order, f.category), Map.fetch!(@severity_order, f.severity), f.rule_id, f.flow_id,
       f.target.id, f.finding_key}
    end)
  end
end
