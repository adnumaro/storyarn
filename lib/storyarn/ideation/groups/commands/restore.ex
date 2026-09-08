defmodule Storyarn.Ideation.Groups.Commands.Restore do
  @moduledoc false
  import Storyarn.Ideation.Groups.Rules.Input, only: [valid_id: 1, valid_version: 1]

  alias Storyarn.Ideation.Groups.Execution.Mutation
  alias Storyarn.Ideation.Groups.Execution.Transaction
  alias Storyarn.Ideation.Groups.Rules.Input

  def run(scope, project_id, session_id, id, expected, attrs)
      when valid_id(id) and valid_version(expected) and is_map(attrs) do
    with {:ok, key} <- Input.request_key(attrs),
         {:ok, ids} <- Input.ids(Input.get(attrs, :idea_ids)),
         {:ok, deleted_at} <- Input.deletion(Input.get(attrs, :deleted_at)) do
      normalized = %{idea_ids: ids, deleted_at: deleted_at}

      Transaction.run(
        scope,
        project_id,
        session_id,
        %{
          operation: "restore",
          group_id: id,
          version: expected,
          request_key: key,
          attrs: normalized
        },
        &Mutation.restore(&1, id, expected, normalized, &2, &3)
      )
    end
  end

  def run(_, _, _, _, _, _), do: {:error, :invalid_group}
end
