defmodule Storyarn.Ideation.Decisions.Commands.Propose do
  @moduledoc false

  alias Storyarn.Ideation.Decisions.Execution.Transaction
  alias Storyarn.Ideation.Decisions.Rules.Input

  def run(scope, project_id, session_id, attrs) do
    with {:ok, attrs, key} <- Input.command(attrs) do
      Transaction.run(scope, project_id, session_id, %{
        operation: "propose",
        id: nil,
        version: nil,
        attrs: attrs,
        key: key
      })
    end
  end
end
