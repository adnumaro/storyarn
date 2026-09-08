defmodule Storyarn.Ideation.Groups.Commands.Create do
  @moduledoc false
  alias Storyarn.Ideation.Groups.Execution.Mutation
  alias Storyarn.Ideation.Groups.Execution.Transaction
  alias Storyarn.Ideation.Groups.Rules.Input

  def run(scope, project_id, session_id, attrs) when is_map(attrs) do
    with {:ok, key} <- Input.request_key(attrs),
         {:ok, content} <- Input.content(attrs),
         {:ok, ids} <- Input.ids(Input.get(attrs, :idea_ids)),
         true <- length(ids) >= 2,
         {:ok, canvas} <- Input.canvas(Input.get(attrs, :canvas)) do
      normalized =
        %{title: nil, synthesis: nil}
        |> Map.merge(content)
        |> Map.merge(%{idea_ids: ids, canvas: canvas})

      Transaction.run(
        scope,
        project_id,
        session_id,
        %{operation: "create", group_id: nil, version: nil, request_key: key, attrs: normalized},
        &Mutation.create(&1, normalized, &2, &3)
      )
    else
      false -> {:error, :invalid_group_members}
      error -> error
    end
  end

  def run(_, _, _, _), do: {:error, :invalid_group}
end
