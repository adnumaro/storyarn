defmodule Storyarn.Ideation.Ideas.Commands.Connect do
  @moduledoc false
  import Storyarn.Ideation.Ideas.Rules.Input, only: [valid_id: 1]

  alias Storyarn.Ideation.Ideas.Execution.Connections
  alias Storyarn.Ideation.Ideas.Execution.Transaction

  # Setting membership is idempotent. It cannot overwrite another move or link.
  def run(scope, project_id, session_id, source_id, target_id, connected?)
      when valid_id(source_id) and valid_id(target_id) and is_boolean(connected?) and source_id != target_id do
    Transaction.run(scope, project_id, session_id, &Connections.connect(&1, source_id, target_id, connected?))
  end

  def run(_, _, _, _, _, _), do: {:error, :invalid_canvas}
end
