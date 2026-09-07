defmodule Storyarn.Ideation.Recovery.References do
  @moduledoc false
  alias Storyarn.Ideation.Recovery.Inventory

  def rewrite(row, collection, project_id, actors, maps) do
    row =
      Enum.reduce(Inventory.actor_fields(), row, fn field, row ->
        if Map.has_key?(row, field), do: Map.update!(row, field, &Map.get(actors, &1)), else: row
      end)

    row
    |> remap(:project_id, fn _ -> project_id end)
    |> remap(:session_id, &lookup(maps, "sessions", &1))
    |> remap(:idea_id, &lookup(maps, "ideas", &1))
    |> remap(:operation_id, &lookup(maps, "reveals", &1))
    |> remap(:source_idea_id, &lookup(maps, "ideas", &1))
    |> rewrite_payload(collection, actors, maps)
  end

  def policy(data, project_id) do
    %{"review_assisted_consent" => Enum.any?(data["rows"]["sessions"], &(&1["project_id"] != project_id))}
  end

  # Delegation to managers belongs to the source project. Importing a private
  # draft must not give a destination owner permission to publish/read it.
  defp rewrite_payload(row, "ideas", _, %{"review_assisted_consent" => true}),
    do: %{row | publication_consent: "author_only"}

  defp rewrite_payload(row, "session_revisions", actors, _) do
    snapshot =
      Enum.reduce(~w(facilitator_id decision_owner_id), row.snapshot, fn field, snapshot ->
        Map.update!(snapshot, field, &Map.get(actors, &1))
      end)

    %{row | snapshot: snapshot}
  end

  defp rewrite_payload(row, "reveals", _, maps) do
    remap_target = fn target -> Map.update!(target, "idea_id", &lookup(maps, "ideas", &1)) end

    selection =
      if row.selection["mode"] == "selected",
        do: Map.update!(row.selection, "targets", &Enum.map(&1, remap_target)),
        else: row.selection

    %{row | selection: selection, manifest: Enum.map(row.manifest, remap_target)}
  end

  defp rewrite_payload(row, _, _, _), do: row
  defp remap(row, field, fun), do: if(Map.has_key?(row, field), do: Map.update!(row, field, fun), else: row)
  defp lookup(_, _, nil), do: nil
  # Sources can point forward during the first insertion pass.
  defp lookup(maps, collection, id), do: Map.get(Map.get(maps, collection, %{}), id)
end
