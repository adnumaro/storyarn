defmodule Storyarn.Flows.Versioning.Commands.Tracked do
  @moduledoc """
  Public Flow version commands whose successful execution emits Flow-owned facts.

  Keeping event construction here prevents presentation adapters from owning
  either the event vocabulary or its payload contract.
  """

  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.Versioning.Commands.VersionLifecycle
  alias Storyarn.Flows.Versioning.Events
  alias Storyarn.Flows.Versioning.Execution.Restore

  @spec create_named_version(term(), Flow.t(), keyword()) ::
          {:ok, term()} | {:error, term()} | {:error, term(), map()}
  def create_named_version(%{user: %{id: user_id}} = scope, %Flow{} = flow, opts)
      when is_integer(user_id) and user_id > 0 and is_list(opts) do
    with :ok <- validate_named_version_title(opts) do
      flow
      |> VersionLifecycle.create_version(user_id, opts)
      |> tap_success(fn _version -> emit_version_event(scope, flow, :version_created) end)
    end
  end

  def create_named_version(_scope, %Flow{}, _opts), do: {:error, :invalid_actor}

  @spec restore_version(term(), Flow.t(), term(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def restore_version(scope, %Flow{} = flow, version, opts) do
    flow
    |> Restore.restore_version(version, opts)
    |> tap_success(fn _restored -> emit_version_event(scope, flow, :version_restored) end)
  end

  @spec record_version_panel_opened(term(), Flow.t()) :: :ok
  def record_version_panel_opened(scope, %Flow{} = flow) do
    emit_version_event(scope, flow, :version_panel_opened)
  end

  @spec record_version_compared(term(), Flow.t()) :: :ok
  def record_version_compared(scope, %Flow{} = flow) do
    emit_version_event(scope, flow, :version_compared)
  end

  defp emit_version_event(scope, flow, event) do
    Events.emit(scope, event, %{entity_type: "flow", project_id: flow.project_id})
  end

  defp tap_success({:ok, value} = result, callback) do
    callback.(value)
    result
  end

  defp tap_success(result, _callback), do: result

  defp validate_named_version_title(opts) do
    case Keyword.get(opts, :title) do
      title when is_binary(title) ->
        if String.trim(title) == "", do: {:error, :title_required}, else: :ok

      _missing ->
        {:error, :title_required}
    end
  end
end
