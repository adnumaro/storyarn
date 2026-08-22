defmodule Storyarn.AI.Context.SubjectRef do
  @moduledoc """
  Server-built selection for one deterministic context package.

  The struct is deliberately not accepted by `ExecutionIntent.new/2`; a
  registered task must derive it from its validated intent.
  """

  alias Storyarn.AI.Context.Contract

  @max_bigint 9_223_372_036_854_775_807

  @enforce_keys [:contract, :kind, :workspace_id, :project_id, :subject_id]
  defstruct [
    :contract,
    :kind,
    :workspace_id,
    :project_id,
    :subject_id,
    selection: %{}
  ]

  @type t :: %__MODULE__{}

  @spec new(module(), atom(), pos_integer(), pos_integer(), pos_integer(), map()) ::
          {:ok, t()} | {:error, :invalid_context_subject}
  def new(contract, kind, workspace_id, project_id, subject_id, selection \\ %{}) do
    validate(%__MODULE__{
      contract: contract,
      kind: kind,
      workspace_id: workspace_id,
      project_id: project_id,
      subject_id: subject_id,
      selection: selection
    })
  end

  @spec validate(t()) :: {:ok, t()} | {:error, :invalid_context_subject}
  def validate(%__MODULE__{} = ref) do
    if Contract.valid?(ref.contract) and is_atom(ref.kind) and valid_id?(ref.workspace_id) and
         valid_id?(ref.project_id) and valid_id?(ref.subject_id) and is_map(ref.selection) and
         ref.contract.validate_subject(ref) == :ok do
      {:ok, ref}
    else
      {:error, :invalid_context_subject}
    end
  end

  def validate(_ref), do: {:error, :invalid_context_subject}

  @doc "Returns the content-free portion that may be persisted with an operation."
  @spec persisted_map(t()) :: {:ok, map()} | {:error, :context_subject_not_persistable}
  def persisted_map(%__MODULE__{} = ref) do
    case validate(ref) do
      {:ok, ref} -> ref.contract.persisted_subject(ref)
      {:error, :invalid_context_subject} -> {:error, :context_subject_not_persistable}
    end
  end

  @spec from_persisted_map(map(), module()) :: {:ok, t()} | {:error, :invalid_context_subject}
  def from_persisted_map(%{} = attrs, contract) do
    if Contract.valid?(contract) do
      case contract.restore_subject(attrs) do
        {:ok, %__MODULE__{contract: ^contract} = ref} -> validate(ref)
        _invalid -> {:error, :invalid_context_subject}
      end
    else
      {:error, :invalid_context_subject}
    end
  end

  def from_persisted_map(_attrs, _contract), do: {:error, :invalid_context_subject}

  @spec valid_id?(term()) :: boolean()
  defp valid_id?(value), do: is_integer(value) and value > 0 and value <= @max_bigint
end
