defmodule Storyarn.Sheets.Editor.Events do
  @moduledoc false

  alias Storyarn.Platform
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.Sheet

  @block_types Block.types()
  @creation_methods ~w(create duplicate wrap_selection)

  @doc "Publishes the product fact for a block created inside a Sheet."
  @spec block_created(term(), Sheet.t(), Block.t(), String.t(), term()) :: :ok
  def block_created(scope_or_user, %Sheet{} = sheet, %Block{} = block, creation_method, block_scope) do
    payload = %{
      block_type: block.type,
      creation_method: creation_method,
      project_id: sheet.project_id,
      scope: block_scope,
      sheet_id: sheet.id
    }

    if valid_payload?(payload) do
      Platform.react_to_event(scope_or_user, :sheets, :block_created, payload)
    else
      :ok
    end
  end

  def block_created(_scope_or_user, _sheet, _block, _creation_method, _block_scope), do: :ok

  defp valid_payload?(payload) do
    payload.block_type in @block_types and payload.creation_method in @creation_methods and
      valid_id?(payload.project_id) and valid_id?(payload.sheet_id) and
      (is_nil(payload.scope) or is_binary(payload.scope))
  end

  defp valid_id?(id), do: is_integer(id) and id > 0
end
