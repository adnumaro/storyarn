defmodule Storyarn.AI.Context.Policy do
  @moduledoc """
  Immutable, task-owned limits for deterministic context construction.

  Callers select a subject, but they cannot widen these limits or change the
  context scope declared by the registered task.
  """

  @scopes [:none, :dialogue, :flow_neighborhood, :sheet, :structural_finding]
  @field_groups [:dialogue, :speaker_blocks, :sheet_blocks]
  @hard_limits %{
    max_depth: 12,
    max_fan_out: 50,
    max_entities: 500,
    max_bytes: 524_288
  }

  @enforce_keys [:scope]
  defstruct [
    :scope,
    :max_depth,
    :max_fan_out,
    :max_entities,
    :max_bytes,
    :tokenizer,
    fields: %{}
  ]

  @type scope :: :none | :dialogue | :flow_neighborhood | :sheet | :structural_finding
  @type t :: %__MODULE__{}

  @spec new(map() | t()) :: {:ok, t()} | {:error, :invalid_context_policy}
  def new(%__MODULE__{} = policy), do: validate(policy)

  def new(%{} = attrs) do
    policy = %__MODULE__{
      scope: value(attrs, :scope),
      max_depth: value(attrs, :max_depth),
      max_fan_out: value(attrs, :max_fan_out),
      max_entities: value(attrs, :max_entities),
      max_bytes: value(attrs, :max_bytes),
      tokenizer: value(attrs, :tokenizer),
      fields: value(attrs, :fields) || %{}
    }

    validate(policy)
  end

  def new(_attrs), do: {:error, :invalid_context_policy}

  @spec valid?(map() | t()) :: boolean()
  def valid?(value), do: match?({:ok, %__MODULE__{}}, new(value))

  @spec none() :: t()
  def none, do: %__MODULE__{scope: :none}

  defp validate(%__MODULE__{scope: :none} = policy) do
    if is_nil(policy.max_depth) and is_nil(policy.max_fan_out) and
         is_nil(policy.max_entities) and is_nil(policy.max_bytes) and
         is_nil(policy.tokenizer) and policy.fields == %{} do
      {:ok, policy}
    else
      {:error, :invalid_context_policy}
    end
  end

  defp validate(%__MODULE__{} = policy) do
    if policy.scope in (@scopes -- [:none]) and
         bounded_nonnegative_integer?(policy.max_depth, @hard_limits.max_depth) and
         bounded_positive_integer?(policy.max_fan_out, @hard_limits.max_fan_out) and
         bounded_positive_integer?(policy.max_entities, @hard_limits.max_entities) and
         bounded_positive_integer?(policy.max_bytes, @hard_limits.max_bytes) and
         valid_tokenizer?(policy.tokenizer) and
         valid_fields?(policy.fields) do
      {:ok, policy}
    else
      {:error, :invalid_context_policy}
    end
  end

  defp valid_fields?(fields) when is_map(fields) do
    Enum.all?(fields, fn
      {group, values} when group in @field_groups and is_list(values) ->
        values != [] and Enum.uniq(values) == values and Enum.all?(values, &bounded_string?/1)

      _other ->
        false
    end)
  end

  defp valid_fields?(_fields), do: false

  defp valid_tokenizer?(nil), do: true

  defp valid_tokenizer?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :count, 1)
  end

  defp valid_tokenizer?(_module), do: false

  defp value(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
  defp bounded_positive_integer?(value, maximum), do: is_integer(value) and value > 0 and value <= maximum

  defp bounded_nonnegative_integer?(value, maximum), do: is_integer(value) and value >= 0 and value <= maximum

  defp bounded_string?(value), do: is_binary(value) and byte_size(value) > 0 and byte_size(value) <= 120
end
