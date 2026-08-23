defmodule Storyarn.Sheets.Events do
  @moduledoc """
  Sheet-owned business event vocabulary.

  Sheets owns the facts and payloads. Platform owns cross-cutting reactions
  such as product metrics, notifications, and future delivery policies.
  """

  alias Storyarn.Platform
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.Sheet

  @event_types [:block_created]

  @block_types Block.types()
  @creation_methods ~w(create duplicate wrap_selection)

  @spec emit(term(), atom(), map()) :: :ok
  def emit(scope_or_user, event_type, payload) when event_type in @event_types and is_map(payload) do
    if valid_payload?(event_type, payload) do
      Platform.react_to_event(scope_or_user, :sheets, event_type, payload)
    else
      :ok
    end
  end

  def emit(_scope_or_user, _event_type, _payload), do: :ok

  @doc "Publishes the product fact for a block created inside a Sheet."
  @spec block_created(term(), Sheet.t(), Block.t(), String.t(), term()) :: :ok
  def block_created(scope_or_user, %Sheet{} = sheet, %Block{} = block, creation_method, block_scope) do
    emit(scope_or_user, :block_created, %{
      block_type: block.type,
      creation_method: creation_method,
      project_id: sheet.project_id,
      scope: block_scope,
      sheet_id: sheet.id
    })
  end

  def block_created(_scope_or_user, _sheet, _block, _creation_method, _block_scope), do: :ok

  defp valid_payload?(:block_created, payload) do
    payload.block_type in @block_types and payload.creation_method in @creation_methods and
      valid_id?(payload.project_id) and valid_id?(payload.sheet_id) and
      (is_nil(payload.scope) or is_binary(payload.scope))
  end

  defp valid_id?(id), do: is_integer(id) and id > 0
end
