defmodule Storyarn.AI.Context.SubjectRef do
  @moduledoc """
  Server-built selection for one deterministic context package.

  The struct is deliberately not accepted by `ExecutionIntent.new/2`; a
  registered task must derive it from its validated intent.
  """

  alias Storyarn.AI.CanonicalJSON

  @kinds [:dialogue, :flow_neighborhood, :sheet, :structural_finding]
  @max_bigint 9_223_372_036_854_775_807

  @enforce_keys [:kind, :workspace_id, :project_id, :subject_id]
  defstruct [
    :kind,
    :workspace_id,
    :project_id,
    :subject_id,
    :response_id,
    :finding,
    block_ids: [],
    evidence: []
  ]

  @type t :: %__MODULE__{}

  @spec dialogue(pos_integer(), pos_integer(), pos_integer(), keyword()) ::
          {:ok, t()} | {:error, :invalid_context_subject}
  def dialogue(workspace_id, project_id, node_id, opts \\ []) do
    build(:dialogue, workspace_id, project_id, node_id, %{
      response_id: Keyword.get(opts, :response_id)
    })
  end

  @spec flow_neighborhood(pos_integer(), pos_integer(), pos_integer()) ::
          {:ok, t()} | {:error, :invalid_context_subject}
  def flow_neighborhood(workspace_id, project_id, node_id) do
    build(:flow_neighborhood, workspace_id, project_id, node_id, %{})
  end

  @spec sheet(pos_integer(), pos_integer(), pos_integer(), keyword()) ::
          {:ok, t()} | {:error, :invalid_context_subject}
  def sheet(workspace_id, project_id, sheet_id, opts \\ []) do
    build(:sheet, workspace_id, project_id, sheet_id, %{
      block_ids: Keyword.get(opts, :block_ids, [])
    })
  end

  @spec structural_finding(pos_integer(), pos_integer(), String.t(), map(), [map()]) ::
          {:ok, t()} | {:error, :invalid_context_subject}
  def structural_finding(workspace_id, project_id, finding_id, finding, evidence \\ []) do
    build(:structural_finding, workspace_id, project_id, finding_id, %{
      finding: finding,
      evidence: evidence
    })
  end

  @spec validate(t()) :: {:ok, t()} | {:error, :invalid_context_subject}
  def validate(%__MODULE__{} = ref) do
    if ref.kind in @kinds and valid_id?(ref.workspace_id) and valid_id?(ref.project_id) and
         valid_subject_id?(ref.kind, ref.subject_id) and valid_response_id?(ref.response_id) and
         valid_ids?(ref.block_ids) and valid_finding?(ref) and valid_evidence?(ref.evidence) do
      {:ok, ref}
    else
      {:error, :invalid_context_subject}
    end
  end

  def validate(_ref), do: {:error, :invalid_context_subject}

  @doc "Returns the content-free portion that may be persisted with an operation."
  @spec persisted_map(t()) :: {:ok, map()} | {:error, :context_subject_not_persistable}
  def persisted_map(%__MODULE__{kind: :structural_finding}), do: {:error, :context_subject_not_persistable}

  def persisted_map(%__MODULE__{} = ref) do
    {:ok,
     %{
       "kind" => Atom.to_string(ref.kind),
       "workspace_id" => ref.workspace_id,
       "project_id" => ref.project_id,
       "subject_id" => ref.subject_id,
       "response_id" => ref.response_id,
       "block_ids" => ref.block_ids
     }}
  end

  @spec from_persisted_map(map()) :: {:ok, t()} | {:error, :invalid_context_subject}
  def from_persisted_map(%{} = attrs) do
    with {:ok, kind} <- persisted_kind(Map.get(attrs, "kind", Map.get(attrs, :kind))) do
      validate(%__MODULE__{
        kind: kind,
        workspace_id: value(attrs, :workspace_id),
        project_id: value(attrs, :project_id),
        subject_id: value(attrs, :subject_id),
        response_id: value(attrs, :response_id),
        block_ids: value(attrs, :block_ids) || []
      })
    end
  end

  def from_persisted_map(_attrs), do: {:error, :invalid_context_subject}

  defp build(kind, workspace_id, project_id, subject_id, attrs) do
    validate(%__MODULE__{
      kind: kind,
      workspace_id: workspace_id,
      project_id: project_id,
      subject_id: subject_id,
      response_id: Map.get(attrs, :response_id),
      block_ids: Map.get(attrs, :block_ids, []),
      finding: Map.get(attrs, :finding),
      evidence: Map.get(attrs, :evidence, [])
    })
  end

  defp valid_finding?(%__MODULE__{kind: :structural_finding, finding: finding}) when is_map(finding),
    do: serializable?(finding)

  defp valid_finding?(%__MODULE__{kind: :structural_finding}), do: false
  defp valid_finding?(%__MODULE__{finding: nil}), do: true
  defp valid_finding?(_ref), do: false

  defp valid_evidence?(evidence) when is_list(evidence), do: Enum.all?(evidence, &valid_evidence_item?/1)
  defp valid_evidence?(_evidence), do: false

  defp valid_evidence_item?(%{} = item) do
    valid_type?(value(item, :type)) and valid_subject_id?(:evidence, value(item, :id)) and
      serializable?(value(item, :content))
  end

  defp valid_evidence_item?(_item), do: false

  defp serializable?(value), do: match?({:ok, _encoded}, CanonicalJSON.encode(value))

  defp valid_ids?(ids) when is_list(ids),
    do: length(ids) <= 1_000 and Enum.uniq(ids) == ids and Enum.all?(ids, &valid_id?/1)

  defp valid_ids?(_ids), do: false
  defp valid_id?(value), do: is_integer(value) and value > 0 and value <= @max_bigint

  defp valid_subject_id?(:structural_finding, value),
    do: is_binary(value) and byte_size(value) > 0 and byte_size(value) <= 200

  defp valid_subject_id?(_kind, value), do: valid_id?(value)

  defp valid_response_id?(nil), do: true
  defp valid_response_id?(value), do: is_binary(value) and byte_size(value) > 0 and byte_size(value) <= 200

  defp valid_type?(value), do: is_binary(value) and byte_size(value) > 0 and byte_size(value) <= 80
  defp value(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))

  defp persisted_kind(value) when is_binary(value) do
    case Enum.find(@kinds, &(Atom.to_string(&1) == value)) do
      nil -> {:error, :invalid_context_subject}
      kind -> {:ok, kind}
    end
  end

  defp persisted_kind(value) when value in @kinds, do: {:ok, value}
  defp persisted_kind(_value), do: {:error, :invalid_context_subject}
end
