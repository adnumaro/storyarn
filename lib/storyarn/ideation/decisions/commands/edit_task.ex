defmodule Storyarn.Ideation.Decisions.Commands.EditTask do
  @moduledoc false
  import Storyarn.Ideation.Decisions.Rules.Input, only: [valid_id: 1]

  alias Storyarn.Ideation.Decisions.Execution.Transaction
  alias Storyarn.Ideation.Decisions.Rules.Input

  def run(scope, project_id, session_id, id, link_key, attrs) when valid_id(id) do
    with {:ok, link_key} <- Input.link_key(link_key),
         {:ok, attrs, key} <- Input.task(attrs) do
      Transaction.run(scope, project_id, session_id, %{
        operation: "edit_task",
        id: id,
        version: nil,
        link_key: link_key,
        attrs: attrs,
        key: key
      })
    end
  end

  def run(_, _, _, _, _, _), do: {:error, :invalid_task_link}
end
