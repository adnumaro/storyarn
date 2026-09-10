defmodule Storyarn.Ideation.Ideas.Commands.UpdateConnections do
  @moduledoc false
  alias Storyarn.Ideation.Ideas.Execution.Connections
  alias Storyarn.Ideation.Ideas.Execution.Transaction
  alias Storyarn.Ideation.Ideas.Rules

  def run(scope, project_id, session_id, attrs) do
    with {:ok, command} <- Rules.Connections.normalize(attrs) do
      Transaction.run(scope, project_id, session_id, &Connections.update(&1, command))
    end
  end
end
