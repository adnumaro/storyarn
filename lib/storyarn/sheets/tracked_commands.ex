defmodule Storyarn.Sheets.TrackedCommands do
  @moduledoc """
  Public Sheet commands whose successful execution emits Sheet-owned facts.

  Keeping event construction here prevents presentation adapters from owning
  either the event vocabulary or its payload contract.
  """

  alias Storyarn.Sheets.Events
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.Versioning

  @spec create_named_version(term(), Sheet.t(), keyword()) ::
          {:ok, term()} | {:error, term()} | {:error, term(), map()}
  def create_named_version(%{user: %{id: user_id}} = scope, %Sheet{} = sheet, opts)
      when is_integer(user_id) and user_id > 0 and is_list(opts) do
    with :ok <- validate_named_version_title(opts) do
      sheet
      |> Versioning.create_version(user_id, opts)
      |> tap_success(fn _version -> emit_version_event(scope, sheet, :version_created) end)
    end
  end

  def create_named_version(_scope, %Sheet{}, _opts), do: {:error, :invalid_actor}

  @spec restore_version(term(), Sheet.t(), term(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def restore_version(scope, %Sheet{} = sheet, version, opts) when is_list(opts) do
    sheet
    |> Versioning.restore_version(version, opts)
    |> tap_success(fn _restored -> emit_version_event(scope, sheet, :version_restored) end)
  end

  @spec record_version_panel_opened(term(), Sheet.t()) :: :ok
  def record_version_panel_opened(scope, %Sheet{} = sheet) do
    emit_version_event(scope, sheet, :version_panel_opened)
  end

  @spec record_version_compared(term(), Sheet.t()) :: :ok
  def record_version_compared(scope, %Sheet{} = sheet) do
    emit_version_event(scope, sheet, :version_compared)
  end

  defp emit_version_event(scope, sheet, event) do
    Events.emit(scope, event, %{entity_type: "sheet", project_id: sheet.project_id})
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
