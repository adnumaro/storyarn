defmodule Storyarn.Ideation.Recovery.Generations do
  @moduledoc false

  alias Storyarn.Ideation.Recovery.Inventory
  alias Storyarn.Ideation.Recovery.References

  # Record identities survive reconstitution. A generation is the complete
  # content of one session, independent of database IDs and replacement time.
  def split(rows) do
    sessions = Map.new(rows["sessions"], &{&1["id"], &1["id"]})
    ideas = Map.new(rows["ideas"], &{&1["id"], &1["session_id"]})

    grouped =
      Map.new(Inventory.tables(), fn {collection, _, parent, _} ->
        {collection,
         Enum.group_by(rows[collection], fn row ->
           case parent do
             :project_id -> sessions[row["id"]]
             :session_id -> row["session_id"]
             :idea_id -> ideas[row["idea_id"]]
           end
         end)}
      end)

    for session <- rows["sessions"] do
      Map.new(grouped, fn {collection, groups} -> {collection, Map.get(groups, session["id"], [])} end)
    end
  end

  def key(rows, project_id, actors, policy) do
    identities =
      Map.new(rows, fn {collection, entries} ->
        {collection, Map.new(entries, &{&1["id"], &1["recovery_identity"]})}
      end)

    maps = Map.merge(identities, policy)

    rows
    |> Map.new(fn {collection, entries} ->
      normalized =
        entries
        |> Enum.map(fn entry ->
          collection
          |> Inventory.decode_row(entry)
          |> References.rewrite(collection, project_id, actors, maps)
          |> Map.put(:id, entry["recovery_identity"])
          |> normalize_replacement(collection)
          |> then(&Inventory.encode_row(collection, &1))
        end)
        |> Enum.sort_by(& &1["recovery_identity"])

      {collection, normalized}
    end)
    |> Inventory.encode()
    |> then(&:crypto.hash(:sha256, &1))
  end

  def match_ids(source, target) do
    Map.new(source, fn {collection, entries} ->
      target_ids = Map.new(target[collection], &{&1["recovery_identity"], &1["id"]})
      {collection, Map.new(entries, &{&1["id"], Map.fetch!(target_ids, &1["recovery_identity"])})}
    end)
  end

  defp normalize_replacement(row, "sessions"), do: %{row | deleted_at: nil}
  defp normalize_replacement(row, _), do: row
end
