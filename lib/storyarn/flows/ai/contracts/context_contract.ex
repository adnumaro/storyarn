defmodule Storyarn.Flows.AI.ContextContract do
  @moduledoc """
  Flow-owned vocabulary and validation for AI context packages.

  The shared AI kernel never needs to know which Flow scopes, selectors or
  evidence types exist. Adding a Flow context capability changes this module
  and its owning task, not a central consumer registry.
  """

  @behaviour Storyarn.AI.Context.Contract

  alias Storyarn.AI.Context.Policy
  alias Storyarn.AI.Context.SubjectRef

  @scopes [:dialogue, :flow_neighborhood]
  @field_groups [:dialogue, :speaker_blocks]
  @included_source_types ~w(flow flow_node flow_connection dialogue_response sheet sheet_block)
  @excluded_source_types @included_source_types ++ ~w(dialogue_response_overflow sheet_block_overflow)
  @max_response_id_bytes 200

  @spec dialogue(pos_integer(), pos_integer(), pos_integer(), keyword()) ::
          {:ok, SubjectRef.t()} | {:error, :invalid_context_subject}
  def dialogue(workspace_id, project_id, node_id, opts \\ []) do
    SubjectRef.new(__MODULE__, :dialogue, workspace_id, project_id, node_id, %{
      response_id: Keyword.get(opts, :response_id)
    })
  end

  @spec flow_neighborhood(pos_integer(), pos_integer(), pos_integer()) ::
          {:ok, SubjectRef.t()} | {:error, :invalid_context_subject}
  def flow_neighborhood(workspace_id, project_id, node_id) do
    SubjectRef.new(__MODULE__, :flow_neighborhood, workspace_id, project_id, node_id)
  end

  @spec response_id(SubjectRef.t()) :: String.t() | nil
  def response_id(%SubjectRef{contract: __MODULE__, kind: :dialogue, selection: %{response_id: response_id}}),
    do: response_id

  @spec from_persisted_subject(map()) :: {:ok, SubjectRef.t()} | {:error, :invalid_context_subject}
  def from_persisted_subject(attrs), do: SubjectRef.from_persisted_map(attrs, __MODULE__)

  @impl true
  def validate_policy(%Policy{scope: scope, fields: fields}) do
    if scope in @scopes and valid_field_groups?(fields),
      do: :ok,
      else: {:error, :invalid_context_policy}
  end

  @impl true
  def validate_subject(%SubjectRef{contract: __MODULE__, kind: :dialogue, selection: selection}) do
    case selection do
      %{response_id: response_id} when map_size(selection) == 1 ->
        if valid_response_id?(response_id),
          do: :ok,
          else: {:error, :invalid_context_subject}

      _invalid ->
        {:error, :invalid_context_subject}
    end
  end

  def validate_subject(%SubjectRef{contract: __MODULE__, kind: :flow_neighborhood, selection: selection})
      when map_size(selection) == 0, do: :ok

  def validate_subject(_ref), do: {:error, :invalid_context_subject}

  @impl true
  def subject_matches_policy?(%SubjectRef{contract: __MODULE__, kind: kind}, %Policy{contract: __MODULE__, scope: kind}),
    do: true

  def subject_matches_policy?(_ref, _policy), do: false

  @impl true
  def persisted_subject(%SubjectRef{contract: __MODULE__} = ref) do
    case validate_subject(ref) do
      :ok -> {:ok, persisted_map(ref)}
      {:error, :invalid_context_subject} -> {:error, :context_subject_not_persistable}
    end
  end

  @impl true
  def restore_subject(%{} = attrs) do
    with {:ok, kind} <- persisted_kind(value(attrs, :kind)),
         [] <- value(attrs, :block_ids) || [] do
      selection = if kind == :dialogue, do: %{response_id: value(attrs, :response_id)}, else: %{}

      SubjectRef.new(
        __MODULE__,
        kind,
        value(attrs, :workspace_id),
        value(attrs, :project_id),
        value(attrs, :subject_id),
        selection
      )
    else
      _invalid -> {:error, :invalid_context_subject}
    end
  end

  def restore_subject(_attrs), do: {:error, :invalid_context_subject}

  @impl true
  def source_type?(type, :included), do: type in @included_source_types
  def source_type?(type, :excluded), do: type in @excluded_source_types
  def source_type?(_type, _location), do: false

  defp persisted_map(%SubjectRef{kind: kind} = ref) do
    %{
      "kind" => Atom.to_string(kind),
      "workspace_id" => ref.workspace_id,
      "project_id" => ref.project_id,
      "subject_id" => ref.subject_id,
      "response_id" => if(kind == :dialogue, do: ref.selection.response_id),
      "block_ids" => []
    }
  end

  defp valid_field_groups?(fields) when is_map(fields), do: Enum.all?(Map.keys(fields), &(&1 in @field_groups))

  defp valid_field_groups?(_fields), do: false

  defp valid_response_id?(nil), do: true

  defp valid_response_id?(value),
    do: is_binary(value) and byte_size(value) > 0 and byte_size(value) <= @max_response_id_bytes

  defp persisted_kind(value) when is_binary(value) do
    case Enum.find(@scopes, &(Atom.to_string(&1) == value)) do
      nil -> {:error, :invalid_context_subject}
      kind -> {:ok, kind}
    end
  end

  defp persisted_kind(value) when value in @scopes, do: {:ok, value}
  defp persisted_kind(_value), do: {:error, :invalid_context_subject}

  defp value(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
end
