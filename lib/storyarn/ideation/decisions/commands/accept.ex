defmodule Storyarn.Ideation.Decisions.Commands.Accept do
  @moduledoc false
  import Storyarn.Ideation.Decisions.Rules.Input, only: [valid_id: 1, valid_version: 1]

  alias Storyarn.Ideation.Decisions.Execution.Transaction
  alias Storyarn.Ideation.Decisions.Rules.Input

  def run(scope, project_id, session_id, id, version, key) when valid_id(id) and valid_version(version) do
    with {:ok, key} <- Input.request_key(key) do
      Transaction.run(scope, project_id, session_id, %{
        operation: "accept",
        id: id,
        version: version,
        attrs: %{},
        key: key
      })
    end
  end

  def run(_, _, _, _, _, _), do: {:error, :invalid_decision}
end
