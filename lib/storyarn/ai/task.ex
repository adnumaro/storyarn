defmodule Storyarn.AI.Task do
  @moduledoc "Immutable, validated definition of one AI product task."

  alias Storyarn.AI.Operation

  @capabilities [:translation, :suggestions, :tasks, :images]
  @data_scopes [:workspace, :project, :entity]
  @lanes [:managed, :personal_byok, :workspace_byok]
  @phases [:execute, :apply, :attach]
  @permissions [:view, :edit_content, :manage_project, :manage_workspace]
  @execution_modes [:inline, :background]
  @destination_types [:panel, :inline_editor, :route, :none]
  @id_format ~r/^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$/

  @enforce_keys [
    :id,
    :module,
    :capability,
    :data_scope,
    :required_domain_permissions,
    :allowed_lanes,
    :input_schema_version,
    :output_schema_version,
    :prompt_version,
    :context_version,
    :max_input_bytes,
    :max_output_bytes,
    :execution_mode,
    :timeout_ms,
    :result_type,
    :result_destination,
    :result_ttl_seconds,
    :personal_byok_allowed?,
    :bulk_allowed?,
    :scheduled_allowed?,
    :result_visibility,
    :enabled?,
    :command_ids
  ]
  defstruct [
    :id,
    :module,
    :capability,
    :data_scope,
    :required_domain_permissions,
    :allowed_lanes,
    :input_schema_version,
    :output_schema_version,
    :prompt_version,
    :context_version,
    :max_input_bytes,
    :max_output_bytes,
    :execution_mode,
    :timeout_ms,
    :result_type,
    :result_destination,
    :result_ttl_seconds,
    :personal_byok_allowed?,
    :bulk_allowed?,
    :scheduled_allowed?,
    :result_visibility,
    :managed_price,
    :enabled?,
    :command_ids,
    provider_options: %{}
  ]

  @type t :: %__MODULE__{}

  @spec new(module(), map()) :: {:ok, t()} | {:error, [atom()]}
  def new(module, attrs) when is_atom(module) and is_map(attrs) do
    task = struct(__MODULE__, Map.put(attrs, :module, module))

    case validation_errors(task) do
      [] -> {:ok, task}
      errors -> {:error, errors}
    end
  end

  @spec enabled?(t()) :: boolean()
  def enabled?(%__MODULE__{enabled?: enabled?}) when is_boolean(enabled?), do: enabled?
  def enabled?(%__MODULE__{enabled?: enabled?}) when is_function(enabled?, 0), do: enabled?.()

  @doc "Returns a deploy-sensitive hash of every field that affects task execution."
  @spec contract_hash(t()) :: String.t()
  def contract_hash(%__MODULE__{} = task) do
    contract = %{
      task: Map.from_struct(%{task | enabled?: enabled?(task)}),
      module_md5: task.module.module_info(:md5)
    }

    contract
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @spec validate_input(t(), map() | list()) :: :ok | {:error, atom()}
  def validate_input(%__MODULE__{module: module}, input) do
    if function_exported?(module, :validate_input, 1), do: module.validate_input(input), else: :ok
  end

  @spec validate_output(t(), term()) :: :ok | {:error, atom()}
  def validate_output(%__MODULE__{module: module}, output) do
    if function_exported?(module, :validate_output, 1), do: module.validate_output(output), else: :ok
  end

  @spec authorize_subject(t(), Storyarn.Accounts.Scope.t(), Storyarn.AI.ExecutionIntent.t() | Operation.t(), atom()) ::
          :ok | {:error, atom()}
  def authorize_subject(%__MODULE__{module: module, data_scope: :entity}, scope, intent_or_operation, phase) do
    module.authorize_subject(scope, intent_or_operation, phase)
  end

  def authorize_subject(%__MODULE__{}, _scope, _intent_or_operation, _phase), do: :ok

  @spec subject_current?(t(), Operation.t()) :: boolean()
  def subject_current?(%__MODULE__{module: module}, operation) do
    if function_exported?(module, :subject_current?, 1), do: module.subject_current?(operation), else: true
  end

  defp validation_errors(task) do
    []
    |> require(is_binary(task.id) and Regex.match?(@id_format, task.id), :invalid_id)
    |> require(task.capability in @capabilities, :invalid_capability)
    |> require(task.data_scope in @data_scopes, :invalid_data_scope)
    |> require(valid_permissions?(task.required_domain_permissions), :invalid_domain_permissions)
    |> require(valid_subset?(task.allowed_lanes, @lanes) and task.allowed_lanes != [], :invalid_lanes)
    |> require(version?(task.input_schema_version), :invalid_input_schema_version)
    |> require(version?(task.output_schema_version), :invalid_output_schema_version)
    |> require(version?(task.prompt_version), :invalid_prompt_version)
    |> require(version?(task.context_version), :invalid_context_version)
    |> require(positive_integer?(task.max_input_bytes), :invalid_max_input_bytes)
    |> require(positive_integer?(task.max_output_bytes), :invalid_max_output_bytes)
    |> require(task.execution_mode in @execution_modes, :invalid_execution_mode)
    |> require(positive_integer?(task.timeout_ms), :invalid_timeout)
    |> require(version?(task.result_type), :invalid_result_type)
    |> require(valid_destination?(task.result_destination), :invalid_result_destination)
    |> require(positive_integer?(task.result_ttl_seconds), :invalid_result_ttl)
    |> require(is_boolean(task.personal_byok_allowed?), :invalid_personal_byok_flag)
    |> require(is_boolean(task.bulk_allowed?), :invalid_bulk_flag)
    |> require(is_boolean(task.scheduled_allowed?), :invalid_scheduled_flag)
    |> require(task.result_visibility in [:actor_private, :shareable], :invalid_result_visibility)
    |> require(valid_managed_price?(task), :invalid_managed_price)
    |> require(is_boolean(task.enabled?) or is_function(task.enabled?, 0), :invalid_enabled)
    |> require(valid_command_ids?(task.command_ids), :invalid_command_ids)
    |> require(is_map(task.provider_options), :invalid_provider_options)
    |> require(
      task.data_scope != :entity or function_exported?(task.module, :authorize_subject, 3),
      :missing_subject_authorizer
    )
  end

  defp valid_permissions?(permissions) when is_map(permissions) do
    Map.has_key?(permissions, :execute) and
      Enum.all?(permissions, fn {phase, permission} -> phase in @phases and permission in @permissions end)
  end

  defp valid_permissions?(_permissions), do: false

  defp valid_subset?(values, allowed) when is_list(values),
    do: Enum.uniq(values) == values and Enum.all?(values, &(&1 in allowed))

  defp valid_subset?(_values, _allowed), do: false

  defp valid_destination?(%{type: type} = destination) when type in @destination_types do
    allowed_keys = if type == :none, do: [:type], else: [:type, :id]
    destination |> Map.keys() |> Enum.all?(&(&1 in allowed_keys)) and (type == :none or version?(destination[:id]))
  end

  defp valid_destination?(_destination), do: false

  defp valid_managed_price?(%{allowed_lanes: lanes, managed_price: price}) when is_list(lanes) do
    if :managed in lanes do
      match?(
        %{id: id, version: version, units: units}
        when is_binary(id) and byte_size(id) > 0 and is_integer(version) and version > 0 and
               is_integer(units) and units > 0,
        price
      )
    else
      is_nil(price)
    end
  end

  defp valid_managed_price?(_task), do: false

  defp valid_command_ids?(ids) when is_list(ids) do
    Enum.uniq(ids) == ids and Enum.all?(ids, &(is_binary(&1) and Regex.match?(@id_format, &1)))
  end

  defp valid_command_ids?(_ids), do: false

  defp version?(value), do: is_binary(value) and byte_size(value) > 0 and byte_size(value) <= 120
  defp positive_integer?(value), do: is_integer(value) and value > 0

  defp require(errors, true, _error), do: errors
  defp require(errors, false, error), do: [error | errors]
end
