defmodule Storyarn.AI.Tasks.FlowFindingExplanation do
  @moduledoc """
  Explains ONE current deterministic structural finding (Slice 7.1) in bounded
  narrative form.

  The client selects which current finding to explain; it never authors the
  finding, its evidence, or the prompt. Identity travels as the exact
  occurrence triple and is re-derived from the authorized flow on every touch
  (context construction, claim, attempt start), so an explanation can never be
  produced against evidence the user is no longer looking at.

  The model returns narrative only: no finding ids, no evidence ids, no
  severity verdicts, no actions. Storyarn attaches the deterministic identity
  to the result.
  """
  @behaviour Storyarn.AI.TaskDefinition

  alias Storyarn.AI.Context.SubjectRef
  alias Storyarn.AI.ExecutionIntent
  alias Storyarn.AI.Operation
  alias Storyarn.Flows
  alias Storyarn.Flows.StructuralAnalysis.Finding
  alias Storyarn.Shared.CanonicalJSON

  @task_id "flows.explain_finding"
  @subject_type "flow_finding"
  @locales ~w(en es)
  @input_keys ~w(finding_key rule_version evidence_fingerprint locale)
  @output_keys ~w(summary why_it_triggers implications suggested_checks)

  @max_text 800
  @max_item 300
  @max_items 5

  @system_prompt """
  You explain one structural finding that Storyarn's deterministic analyzer already produced for a narrative flow graph.

  The finding and its evidence are given to you. They are facts: never dispute them, never restate them as your own conclusion, and never claim Storyarn proved anything beyond what the evidence contains.

  Rules:
  - Explain only the finding you were given. Never mention or invent another problem.
  - Use only the provided evidence. Never guess node contents, ids, or connections that are not there.
  - Never output ids, fingerprints, rule versions, permissions, prices, or links.
  - Never assert that a condition is satisfiable or unsatisfiable; the analyzer is topological, not symbolic.
  - Suggested checks must be things a human can inspect. Never instruct Storyarn to change anything.
  - Write for a narrative designer, not an engineer. Be concrete and short.
  - Write every field in the requested locale.
  """

  @response_schema %{
    "type" => "object",
    "properties" => %{
      "summary" => %{"type" => "string", "maxLength" => @max_text},
      "why_it_triggers" => %{"type" => "string", "maxLength" => @max_text},
      "implications" => %{
        "type" => "array",
        "maxItems" => @max_items,
        "items" => %{"type" => "string", "maxLength" => @max_item}
      },
      "suggested_checks" => %{
        "type" => "array",
        "maxItems" => @max_items,
        "items" => %{"type" => "string", "maxLength" => @max_item}
      }
    },
    "required" => @output_keys,
    "additionalProperties" => false
  }

  @impl true
  def definition do
    config = Application.get_env(:storyarn, __MODULE__, [])

    %{
      id: @task_id,
      capability: :tasks,
      # :entity (not :project) so the policy layer rejects an intent without a
      # subject and routes authorization through authorize_subject/3.
      data_scope: :entity,
      required_domain_permissions: %{execute: :view},
      allowed_lanes: [:managed],
      input_schema_version: "flow-finding-explanation-input-v1",
      output_schema_version: "flow-finding-explanation-output-v1",
      prompt_version: "flow-finding-explanation-prompt-v1",
      context_version: "structural-finding-v1",
      # The builder loads one finding plus its typed evidence and traverses
      # nothing. max_fan_out matches SubjectRef's own 50-evidence cap so the
      # two bounds cannot disagree; anything above max_bytes is truncated and
      # reported in the preflight disclosure rather than silently dropped.
      context_policy: %{
        scope: :structural_finding,
        max_depth: 1,
        max_fan_out: 50,
        max_entities: 64,
        max_bytes: 32_768
      },
      max_input_bytes: 1_024,
      max_output_bytes: 8_192,
      execution_mode: :background,
      timeout_ms: 60_000,
      result_type: "flow_finding_explanation_v1",
      result_destination: %{type: :panel, id: "flow_analysis"},
      result_ttl_seconds: 1_800,
      personal_byok_allowed?: false,
      personal_cost_class: nil,
      bulk_allowed?: false,
      scheduled_allowed?: false,
      result_visibility: :actor_private,
      managed_price: %{
        id: Keyword.get(config, :price_id, "flow-explanation-beta"),
        version: Keyword.get(config, :price_version, 1),
        units: Keyword.get(config, :price_units, 1)
      },
      enabled?: Keyword.get(config, :enabled, true),
      command_ids: [@task_id],
      provider_options: %{
        system_prompt: @system_prompt,
        schema_name: "storyarn_flow_finding_explanation",
        response_schema: @response_schema,
        max_output_tokens: 1_024,
        temperature: 0.2
      }
    }
  end

  @doc "The registered task id, for callers building an intent."
  @spec task_id() :: String.t()
  def task_id, do: @task_id

  @doc "The operation subject for one finding — the durable, re-derivable identity."
  @spec subject(pos_integer(), Finding.t()) ::
          %{type: String.t(), id: pos_integer(), revision: String.t()}
  def subject(flow_id, finding) do
    %{
      type: @subject_type,
      id: flow_id,
      revision: Flows.encode_structural_finding_identity(finding)
    }
  end

  @doc """
  The deterministic idempotency key for one explanation attempt.

  Derived from the actor plus the exact occurrence, so two surfaces racing on
  the same finding replay ONE operation instead of buying two: the kernel's
  `replay_or_create` returns the existing row when the intent matches. Paying
  again requires raising `attempt`, which only an explicit rerun does.

  The subject revision is part of the key, so an occurrence that moved gets its
  own key and can never collide with a stale intent.
  """
  @spec idempotency_key(pos_integer(), Finding.t(), non_neg_integer()) :: String.t()
  def idempotency_key(actor_id, finding, attempt) when is_integer(actor_id) and is_integer(attempt) and attempt >= 0 do
    CanonicalJSON.hash!(%{
      "actor_id" => actor_id,
      "task_id" => @task_id,
      "subject_revision" => Flows.encode_structural_finding_identity(finding),
      "attempt" => attempt
    })
  end

  @doc "The validated request payload for one finding in one locale."
  @spec input(Finding.t(), String.t()) :: map()
  def input(finding, locale) do
    identity = Flows.structural_finding_identity(finding)

    %{
      "finding_key" => identity.finding_key,
      "rule_version" => identity.rule_version,
      "evidence_fingerprint" => identity.evidence_fingerprint,
      "locale" => locale
    }
  end

  # ===========================================================================
  # Contract callbacks
  # ===========================================================================

  @impl true
  def validate_input(%{"locale" => locale} = input) when is_map(input) do
    with true <- Enum.sort(Map.keys(input)) == Enum.sort(@input_keys),
         true <- locale in @locales,
         {:ok, _identity} <- decode_input_identity(input) do
      :ok
    else
      _invalid -> {:error, :invalid_explanation_input}
    end
  end

  def validate_input(_input), do: {:error, :invalid_explanation_input}

  @impl true
  def validate_output(output) when is_map(output) do
    with true <- Enum.sort(Map.keys(output)) == Enum.sort(@output_keys),
         true <- bounded_text?(output["summary"]),
         true <- bounded_text?(output["why_it_triggers"]),
         true <- bounded_list?(output["implications"]),
         true <- bounded_list?(output["suggested_checks"]) do
      :ok
    else
      _invalid -> {:error, :invalid_explanation_output}
    end
  end

  def validate_output(_output), do: {:error, :invalid_explanation_output}

  @impl true
  def authorize_subject(_scope, source, _phase) do
    with {:ok, parts} <- subject_parts(source),
         %Flows.Flow{} <- Flows.get_flow_brief(parts.project_id, parts.flow_id) do
      :ok
    else
      nil -> {:error, :unknown_flow}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def subject_current?(%Operation{} = operation) do
    match?({:ok, _finding}, current_finding(operation))
  end

  def subject_current?(_operation), do: false

  @impl true
  def context_subject(source) do
    with {:ok, parts} <- subject_parts(source),
         {:ok, finding} <- current_finding(source) do
      SubjectRef.structural_finding(
        parts.workspace_id,
        parts.project_id,
        finding.finding_id,
        Flows.structural_finding_context_map(finding),
        finding.evidence
      )
    end
  end

  # ===========================================================================
  # Private
  # ===========================================================================

  # One re-derivation path for both the pre-execution intent and the durable
  # operation the background worker reauthorizes.
  defp current_finding(source) do
    with {:ok, parts} <- subject_parts(source) do
      Flows.fetch_current_structural_finding(parts.project_id, parts.flow_id, parts.identity)
    end
  end

  defp subject_parts(%ExecutionIntent{
         workspace_id: workspace_id,
         project_id: project_id,
         subject: %{type: @subject_type, id: flow_id, revision: revision}
       }) do
    build_parts(workspace_id, project_id, flow_id, revision)
  end

  defp subject_parts(%Operation{
         workspace_id_snapshot: workspace_id,
         project_id_snapshot: project_id,
         subject_type: @subject_type,
         subject_id: flow_id,
         subject_revision: revision
       }) do
    build_parts(workspace_id, project_id, flow_id, revision)
  end

  defp subject_parts(_source), do: {:error, :invalid_context_subject}

  defp build_parts(workspace_id, project_id, flow_id, revision)
       when is_integer(workspace_id) and is_integer(project_id) and is_integer(flow_id) do
    case Flows.decode_structural_finding_identity(revision) do
      {:ok, identity} ->
        {:ok,
         %{
           workspace_id: workspace_id,
           project_id: project_id,
           flow_id: flow_id,
           identity: identity
         }}

      {:error, _reason} ->
        {:error, :invalid_context_subject}
    end
  end

  defp build_parts(_workspace_id, _project_id, _flow_id, _revision), do: {:error, :invalid_context_subject}

  # Round-trips through the canonical encoding so the input format cannot drift
  # from the durable subject format. The guard is what keeps a string
  # `rule_version` from interpolating into a valid-looking encoding.
  defp decode_input_identity(%{"finding_key" => key, "rule_version" => version, "evidence_fingerprint" => fingerprint})
       when is_binary(key) and is_integer(version) and is_binary(fingerprint) do
    %{finding_key: key, rule_version: version, evidence_fingerprint: fingerprint}
    |> Flows.encode_structural_finding_identity()
    |> Flows.decode_structural_finding_identity()
  end

  defp decode_input_identity(_input), do: {:error, :invalid_finding_identity}

  defp bounded_text?(value), do: is_binary(value) and value != "" and String.length(value) <= @max_text

  defp bounded_list?(value) when is_list(value) do
    length(value) <= @max_items and Enum.all?(value, &(is_binary(&1) and &1 != "" and String.length(&1) <= @max_item))
  end

  defp bounded_list?(_value), do: false
end
