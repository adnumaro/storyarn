defmodule Storyarn.Ideation.Decisions.Commands.Declare do
  @moduledoc false
  import Storyarn.Ideation.Decisions.Rules.Input, only: [valid_id: 1, valid_version: 1]

  alias Storyarn.Ideation.Decisions.Execution.Transaction
  alias Storyarn.Ideation.Decisions.Rules.Input

  def run(scope, project_id, session_id, id, agreement, attrs) when valid_id(id) and valid_version(agreement) do
    with {:ok, attrs, key} <- Input.application(attrs) do
      Transaction.run(scope, project_id, session_id, %{
        operation: "declare",
        id: id,
        version: nil,
        agreement: agreement,
        attrs: attrs,
        key: key
      })
    end
  end

  def run(_, _, _, _, _, _), do: {:error, :invalid_application}
end
