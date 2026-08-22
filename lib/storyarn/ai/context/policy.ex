defmodule Storyarn.AI.Context.Policy do
  @moduledoc """
  Immutable, task-owned limits for deterministic context construction.

  Callers select a subject, but they cannot widen these limits or change the
  context scope declared by the registered task.
  """

  alias Storyarn.AI.Context.Contract

  @hard_limits %{
    max_depth: 12,
    max_fan_out: 50,
    max_entities: 500,
    max_bytes: 524_288
  }

  @enforce_keys [:scope]
  defstruct [
    :scope,
    :contract,
    :max_depth,
    :max_fan_out,
    :max_entities,
    :max_bytes,
    :tokenizer,
    fields: %{}
  ]

  @type scope :: atom()
  @type t :: %__MODULE__{}

  @spec new(map() | t(), module() | nil) :: {:ok, t()} | {:error, :invalid_context_policy}
  def new(attrs, contract \\ nil)

  def new(%__MODULE__{} = policy, contract) do
    policy
    |> Map.put(:contract, contract || policy.contract)
    |> validate()
  end

  def new(%{} = attrs, contract) do
    policy = %__MODULE__{
      scope: value(attrs, :scope),
      contract: contract,
      max_depth: value(attrs, :max_depth),
      max_fan_out: value(attrs, :max_fan_out),
      max_entities: value(attrs, :max_entities),
      max_bytes: value(attrs, :max_bytes),
      tokenizer: value(attrs, :tokenizer),
      fields: value(attrs, :fields) || %{}
    }

    validate(policy)
  end

  def new(_attrs, _contract), do: {:error, :invalid_context_policy}

  @spec valid?(map() | t(), module() | nil) :: boolean()
  def valid?(value, contract \\ nil), do: match?({:ok, %__MODULE__{}}, new(value, contract))

  @spec none() :: t()
  def none, do: %__MODULE__{scope: :none, contract: nil}

  defp validate(%__MODULE__{scope: :none} = policy) do
    if is_nil(policy.max_depth) and is_nil(policy.max_fan_out) and
         is_nil(policy.max_entities) and is_nil(policy.max_bytes) and
         is_nil(policy.tokenizer) and policy.fields == %{} and is_nil(policy.contract) do
      {:ok, policy}
    else
      {:error, :invalid_context_policy}
    end
  end

  defp validate(%__MODULE__{} = policy) do
    with true <- valid_contextual_policy_shape?(policy),
         :ok <- policy.contract.validate_policy(policy) do
      {:ok, policy}
    else
      _invalid -> {:error, :invalid_context_policy}
    end
  end

  defp valid_contextual_policy_shape?(policy) do
    Enum.all?([
      contextual_scope?(policy.scope),
      Contract.valid?(policy.contract),
      bounded_nonnegative_integer?(policy.max_depth, @hard_limits.max_depth),
      bounded_positive_integer?(policy.max_fan_out, @hard_limits.max_fan_out),
      bounded_positive_integer?(policy.max_entities, @hard_limits.max_entities),
      bounded_positive_integer?(policy.max_bytes, @hard_limits.max_bytes),
      valid_tokenizer?(policy.tokenizer),
      valid_fields?(policy.fields)
    ])
  end

  defp valid_fields?(fields) when is_map(fields) do
    Enum.all?(fields, fn
      {group, values} when is_atom(group) and is_list(values) ->
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

  defp contextual_scope?(scope), do: is_atom(scope) and scope != :none

  defp value(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
  defp bounded_positive_integer?(value, maximum), do: is_integer(value) and value > 0 and value <= maximum

  defp bounded_nonnegative_integer?(value, maximum), do: is_integer(value) and value >= 0 and value <= maximum

  defp bounded_string?(value), do: is_binary(value) and byte_size(value) > 0 and byte_size(value) <= 120
end
