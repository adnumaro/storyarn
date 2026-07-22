defmodule Storyarn.AI.ExecutionIntent do
  @moduledoc """
  Server-built request for a registered AI task.

  The struct intentionally has no provider, model, price, credential, role or
  permission fields. Those values are resolved by policy and route-option
  lookup, never accepted from a caller-controlled payload.
  """

  alias Storyarn.Accounts.Scope
  alias Storyarn.AI.CanonicalJSON

  @max_bigint 9_223_372_036_854_775_807

  @derive {Inspect, except: [:scope, :input, :requested_route_ref]}
  @enforce_keys [:scope, :workspace_id, :task_id, :input, :input_hash]
  defstruct [
    :scope,
    :workspace_id,
    :project_id,
    :task_id,
    :input,
    :input_hash,
    :subject,
    :requested_route_ref,
    :idempotency_key,
    bulk?: false,
    scheduled?: false
  ]

  @type subject :: %{type: String.t(), id: pos_integer(), revision: String.t()}

  @type t :: %__MODULE__{
          scope: Scope.t(),
          workspace_id: pos_integer(),
          project_id: pos_integer() | nil,
          task_id: String.t(),
          input: map() | list(),
          input_hash: String.t(),
          subject: subject() | nil,
          requested_route_ref: String.t() | nil,
          idempotency_key: String.t() | nil,
          bulk?: boolean(),
          scheduled?: boolean()
        }

  @spec new(Scope.t(), map()) :: {:ok, t()} | {:error, atom()}
  def new(%Scope{user: %{id: user_id}} = scope, attrs) when is_integer(user_id) and is_map(attrs) do
    with {:ok, workspace_id} <- positive_id(Map.get(attrs, :workspace_id)),
         {:ok, project_id} <- optional_positive_id(Map.get(attrs, :project_id)),
         {:ok, task_id} <- bounded_string(Map.get(attrs, :task_id), 120),
         {:ok, input} <- structured_input(Map.get(attrs, :input)),
         {:ok, input_hash} <- CanonicalJSON.hash(input),
         {:ok, subject} <- subject(Map.get(attrs, :subject)),
         {:ok, route_ref} <- optional_bounded_string(Map.get(attrs, :requested_route_ref), 128),
         {:ok, idempotency_key} <- optional_bounded_string(Map.get(attrs, :idempotency_key), 64),
         {:ok, bulk?} <- boolean(Map.get(attrs, :bulk?, false)),
         {:ok, scheduled?} <- boolean(Map.get(attrs, :scheduled?, false)) do
      {:ok,
       %__MODULE__{
         scope: scope,
         workspace_id: workspace_id,
         project_id: project_id,
         task_id: task_id,
         input: input,
         input_hash: input_hash,
         subject: subject,
         requested_route_ref: route_ref,
         idempotency_key: idempotency_key,
         bulk?: bulk?,
         scheduled?: scheduled?
       }}
    end
  end

  def new(_scope, _attrs), do: {:error, :invalid_scope}

  defp positive_id(value) when is_integer(value) and value > 0 and value <= @max_bigint, do: {:ok, value}
  defp positive_id(_value), do: {:error, :invalid_workspace}

  defp optional_positive_id(nil), do: {:ok, nil}
  defp optional_positive_id(value) when is_integer(value) and value > 0 and value <= @max_bigint, do: {:ok, value}
  defp optional_positive_id(_value), do: {:error, :invalid_project}

  defp bounded_string(value, max) when is_binary(value) and byte_size(value) > 0 and byte_size(value) <= max,
    do: {:ok, value}

  defp bounded_string(_value, _max), do: {:error, :invalid_string}

  defp optional_bounded_string(nil, _max), do: {:ok, nil}
  defp optional_bounded_string(value, max), do: bounded_string(value, max)

  defp structured_input(value) when is_map(value) or is_list(value) do
    case CanonicalJSON.encode(value) do
      {:ok, _encoded} -> {:ok, value}
      {:error, _reason} -> {:error, :invalid_input}
    end
  end

  defp structured_input(_value), do: {:error, :invalid_input}

  defp subject(nil), do: {:ok, nil}

  defp subject(%{type: type, id: id, revision: revision})
       when is_binary(type) and byte_size(type) > 0 and byte_size(type) <= 80 and is_integer(id) and id > 0 and
              id <= @max_bigint and is_binary(revision) and byte_size(revision) > 0 and byte_size(revision) <= 200 do
    {:ok, %{type: type, id: id, revision: revision}}
  end

  defp subject(_value), do: {:error, :invalid_subject}

  defp boolean(value) when is_boolean(value), do: {:ok, value}
  defp boolean(_value), do: {:error, :invalid_boolean}
end
