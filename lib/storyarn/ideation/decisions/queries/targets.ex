defmodule Storyarn.Ideation.Decisions.Queries.Targets do
  @moduledoc false

  alias Storyarn.Ideation.References

  # A decision names the content it affects; it never reads or writes that
  # content. Existing targets are pinned by identity so a replaced Sheet, Flow
  # or Scene reads as unavailable instead of silently pointing at a newcomer.
  def capture(_scope, _project_id, []), do: {:ok, %{targets: %{"items" => []}, target_context: "{}"}}

  def capture(scope, project_id, targets) do
    with {:ok, live} <- live(scope, project_id, for(%{id: id, type: type} <- targets, do: {type, id})),
         {:ok, items, context} <- Enum.reduce_while(targets, {:ok, [], %{}}, &pin_next(&1, &2, live)) do
      {:ok, %{targets: %{"items" => items}, target_context: Jason.encode!(context)}}
    end
  end

  defp pin_next(target, {:ok, items, context}, live) do
    case pin(target, live) do
      {:ok, item, label} -> {:cont, {:ok, items ++ [item], Map.put(context, item["key"], %{"label" => label})}}
      :error -> {:halt, {:error, :targets_unavailable}}
    end
  end

  defp pin(%{id: id, type: type}, live) do
    case live[{type, id}] do
      %{identity: identity, name: name} ->
        {:ok, %{"key" => Ecto.UUID.generate(), "type" => type, "id" => id, "identity" => identity}, name}

      _ ->
        :error
    end
  end

  defp pin(%{label: label, type: type}, _live),
    do: {:ok, %{"key" => Ecto.UUID.generate(), "type" => type, "id" => nil, "identity" => nil}, label}

  # Current names of the pinned targets the reader may see, keyed by type and ID.
  def live(_scope, _project_id, []), do: {:ok, %{}}

  def live(scope, project_id, pairs) do
    pairs
    |> Enum.uniq()
    |> Enum.chunk_every(50)
    |> Enum.reduce_while({:ok, %{}}, fn chunk, {:ok, acc} ->
      case References.targets(scope, project_id, chunk) do
        {:ok, rows} -> {:cont, {:ok, Map.merge(acc, rows)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  def pairs(revisions) do
    for revision <- revisions, item <- revision.targets["items"], not is_nil(item["id"]), do: {item["type"], item["id"]}
  end
end
