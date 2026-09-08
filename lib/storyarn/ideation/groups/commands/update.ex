defmodule Storyarn.Ideation.Groups.Commands.Update do
  @moduledoc false
  import Storyarn.Ideation.Groups.Rules.Input, only: [valid_id: 1, valid_version: 1]

  alias Storyarn.Ideation.Groups.Execution.Mutation
  alias Storyarn.Ideation.Groups.Execution.Transaction
  alias Storyarn.Ideation.Groups.Rules.Input

  def run(scope, project_id, session_id, id, expected, attrs)
      when valid_id(id) and valid_version(expected) and is_map(attrs) do
    with {:ok, key} <- Input.request_key(attrs),
         {:ok, content} <- Input.content(attrs),
         {:ok, membership} <- membership_attrs(attrs, content),
         {:ok, normalized} <- canvas_attrs(attrs, membership) do
      Transaction.run(
        scope,
        project_id,
        session_id,
        %{
          operation: "update",
          group_id: id,
          version: expected,
          request_key: key,
          attrs: normalized
        },
        &Mutation.update(&1, id, expected, normalized, &2, &3)
      )
    end
  end

  def run(_, _, _, _, _, _), do: {:error, :invalid_group}

  defp membership_attrs(attrs, content) do
    if Map.has_key?(attrs, :idea_ids) or Map.has_key?(attrs, "idea_ids") do
      with {:ok, ids} <- Input.ids(Input.get(attrs, :idea_ids)),
           do: {:ok, Map.put(content, :idea_ids, ids)}
    else
      {:ok, content}
    end
  end

  defp canvas_attrs(attrs, normalized) do
    if Map.has_key?(attrs, :canvas) or Map.has_key?(attrs, "canvas") do
      with {:ok, canvas} <- Input.anchor(Input.get(attrs, :canvas)),
           do: {:ok, Map.put(normalized, :canvas, canvas)}
    else
      {:ok, normalized}
    end
  end
end
