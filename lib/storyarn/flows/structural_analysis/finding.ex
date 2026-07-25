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
  @identity_separator "|"
  @fingerprint_format ~r/\A[0-9a-f]{64}\z/

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
  @type identity :: %{
          finding_key: String.t(),
          rule_version: pos_integer(),
          evidence_fingerprint: String.t()
        }
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

  @doc """
  The exact occurrence triple that identifies one finding.

  A dismissal, an AI explanation, or any other disposition binds to this triple
  and to nothing else: a changed rule version or changed evidence is a
  different occurrence, never a silent substitution.
  """
  @spec identity(t()) :: identity()
  def identity(%__MODULE__{} = finding) do
    %{
      finding_key: finding.finding_key,
      rule_version: finding.rule_version,
      evidence_fingerprint: finding.evidence_fingerprint
    }
  end

  @doc """
  Durable single-string encoding of `identity/1`.

  Used where a store only offers one opaque revision field (the AI operation
  `subject_revision`). `finding_key` is built from rule id, flow id and target,
  none of which can contain the separator.
  """
  @spec encode_identity(t() | identity()) :: String.t()
  def encode_identity(%__MODULE__{} = finding), do: finding |> identity() |> encode_identity()

  def encode_identity(%{finding_key: key, rule_version: version, evidence_fingerprint: fingerprint}) do
    "#{key}#{@identity_separator}#{version}#{@identity_separator}#{fingerprint}"
  end

  @doc "Parses `encode_identity/1`. Fails closed on anything else."
  @spec decode_identity(term()) :: {:ok, identity()} | {:error, :invalid_finding_identity}
  def decode_identity(encoded) when is_binary(encoded) do
    with [key, version, fingerprint] <- String.split(encoded, @identity_separator),
         true <- key != "",
         {version, ""} <- Integer.parse(version),
         true <- version > 0,
         true <- fingerprint =~ @fingerprint_format do
      {:ok, %{finding_key: key, rule_version: version, evidence_fingerprint: fingerprint}}
    else
      _invalid -> {:error, :invalid_finding_identity}
    end
  end

  def decode_identity(_encoded), do: {:error, :invalid_finding_identity}

  @doc """
  CanonicalJSON-safe representation (string keys and values only) — the form
  Slice 7.2 passes to `SubjectRef.structural_finding/5`.
  """
  @spec to_context_map(t()) :: map()
  def to_context_map(%__MODULE__{} = finding) do
    %{
      "finding_key" => finding.finding_key,
      "rule_id" => finding.rule_id,
      "rule_version" => finding.rule_version,
      "category" => to_string(finding.category),
      "severity" => to_string(finding.severity),
      "flow_id" => finding.flow_id,
      "target" => %{"type" => to_string(finding.target.type), "id" => finding.target.id},
      "evidence_fingerprint" => finding.evidence_fingerprint,
      "details" => Map.new(finding.details, fn {k, v} -> {to_string(k), v} end)
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
