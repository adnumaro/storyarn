defmodule Storyarn.Sheets.AI.ContextContract do
  @moduledoc """
  Sheet-owned vocabulary and validation for AI context packages.

  This contract keeps Sheet selectors, field groups and evidence types out of
  the provider-neutral AI kernel.
  """

  @behaviour Storyarn.AI.Context.Contract

  alias Storyarn.AI.Context.Policy
  alias Storyarn.AI.Context.SubjectRef

  @scope :sheet
  @persisted_scope "sheet"
  @field_groups [:sheet_blocks]
  @source_types ~w(flow sheet sheet_block)
  @max_selected_blocks 1_000

  @spec sheet(pos_integer(), pos_integer(), pos_integer(), keyword()) ::
          {:ok, SubjectRef.t()} | {:error, :invalid_context_subject}
  def sheet(workspace_id, project_id, sheet_id, opts \\ []) do
    SubjectRef.new(__MODULE__, @scope, workspace_id, project_id, sheet_id, %{
      block_ids: Keyword.get(opts, :block_ids, [])
    })
  end

  @spec block_ids(SubjectRef.t()) :: [pos_integer()]
  def block_ids(%SubjectRef{contract: __MODULE__, kind: @scope, selection: %{block_ids: block_ids}}), do: block_ids

  @spec from_persisted_subject(map()) :: {:ok, SubjectRef.t()} | {:error, :invalid_context_subject}
  def from_persisted_subject(attrs), do: SubjectRef.from_persisted_map(attrs, __MODULE__)

  @impl true
  def validate_policy(%Policy{scope: @scope, fields: fields}) do
    if Enum.all?(Map.keys(fields), &(&1 in @field_groups)),
      do: :ok,
      else: {:error, :invalid_context_policy}
  end

  def validate_policy(_policy), do: {:error, :invalid_context_policy}

  @impl true
  def validate_subject(%SubjectRef{contract: __MODULE__, kind: @scope, selection: %{block_ids: block_ids} = selection})
      when map_size(selection) == 1 do
    if valid_ids?(block_ids),
      do: :ok,
      else: {:error, :invalid_context_subject}
  end

  def validate_subject(_ref), do: {:error, :invalid_context_subject}

  @impl true
  def subject_matches_policy?(%SubjectRef{contract: __MODULE__, kind: @scope}, %Policy{
        contract: __MODULE__,
        scope: @scope
      }), do: true

  def subject_matches_policy?(_ref, _policy), do: false

  @impl true
  def persisted_subject(%SubjectRef{contract: __MODULE__} = ref) do
    case validate_subject(ref) do
      :ok ->
        {:ok,
         %{
           "kind" => Atom.to_string(@scope),
           "workspace_id" => ref.workspace_id,
           "project_id" => ref.project_id,
           "subject_id" => ref.subject_id,
           "response_id" => nil,
           "block_ids" => ref.selection.block_ids
         }}

      {:error, :invalid_context_subject} ->
        {:error, :context_subject_not_persistable}
    end
  end

  @impl true
  def restore_subject(%{} = attrs) do
    with kind when kind in [@scope, @persisted_scope] <- value(attrs, :kind),
         nil <- value(attrs, :response_id) do
      SubjectRef.new(
        __MODULE__,
        @scope,
        value(attrs, :workspace_id),
        value(attrs, :project_id),
        value(attrs, :subject_id),
        %{block_ids: value(attrs, :block_ids) || []}
      )
    else
      _invalid -> {:error, :invalid_context_subject}
    end
  end

  def restore_subject(_attrs), do: {:error, :invalid_context_subject}

  @impl true
  def source_type?(type, location) when location in [:included, :excluded], do: type in @source_types
  def source_type?(_type, _location), do: false

  defp valid_ids?(ids) when is_list(ids),
    do: length(ids) <= @max_selected_blocks and Enum.uniq(ids) == ids and Enum.all?(ids, &positive_id?/1)

  defp valid_ids?(_ids), do: false
  defp positive_id?(value), do: is_integer(value) and value > 0
  defp value(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
end
