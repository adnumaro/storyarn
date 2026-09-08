defmodule Storyarn.Ideation.Recovery.Restore do
  @moduledoc false
  import Ecto.Query
  import Storyarn.Ideation.Recovery.References, only: [rewrite: 5, policy: 2]

  alias Storyarn.Ideation.Recovery.Capsule
  alias Storyarn.Ideation.Recovery.Capture
  alias Storyarn.Ideation.Recovery.Generations
  alias Storyarn.Ideation.Recovery.Inventory
  alias Storyarn.Ideation.Recovery.Records
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  def run(project_id, capsule) do
    if Repo.in_transaction?(), do: restore(project_id, capsule), else: {:error, :ideation_recovery_transaction_required}
  end

  defp restore(project_id, nil) do
    if Repo.exists?(from s in "ideation_sessions", where: s.project_id == ^project_id and is_nil(s.deleted_at)),
      do: {:error, :legacy_snapshot_excludes_ideation},
      else: {:ok, %{}}
  end

  defp restore(project_id, capsule) do
    with {:ok, data} <- Capsule.open(capsule),
         {:ok, actors} <- Records.resolve_actors(data["actors"]),
         {:ok, current} <- Records.capture(project_id) do
      now = DateTime.to_naive(TimeHelpers.now())

      Repo.update_all(from(s in "ideation_sessions", where: s.project_id == ^project_id and is_nil(s.deleted_at)),
        set: [deleted_at: now]
      )

      maps = restore_generations(data, current, project_id, actors)

      with :ok <- verify(project_id, capsule, maps),
           {:ok, _capsule} <- Capture.run(project_id) do
        {:ok, maps}
      end
    end
  end

  defp restore_generations(data, current, project_id, actors) do
    current_actors = Map.new(current["actors"], fn {id, _} -> {String.to_integer(id), String.to_integer(id)} end)
    policy = policy(data, project_id)

    existing =
      current["rows"]
      |> Generations.split()
      |> Map.new(&{Generations.key(&1, project_id, current_actors, %{}), &1})

    empty_maps = Map.new(Inventory.tables(), fn {collection, _, _, _} -> {collection, %{}} end)

    data["rows"]
    |> Generations.split()
    |> Enum.reduce(Map.merge(empty_maps, policy), fn rows, maps ->
      restored =
        case existing[Generations.key(rows, project_id, actors, policy)] do
          nil -> insert_records(rows, project_id, actors, policy)
          target -> reuse_generation(rows, target)
        end

      Map.merge(maps, restored, &merge_maps/3)
    end)
  end

  defp merge_maps(_collection, old, new) when is_map(old), do: Map.merge(old, new)
  defp merge_maps(_key, _old, new), do: new

  defp reuse_generation(rows, target) do
    maps = Generations.match_ids(rows, target)
    [session] = rows["sessions"]
    row = Inventory.decode_row("sessions", session)
    id = maps["sessions"][session["id"]]
    Repo.update_all(from(s in "ideation_sessions", where: s.id == ^id), set: [deleted_at: row.deleted_at])
    maps
  end

  def verify(_project_id, nil, maps) when map_size(maps) == 0, do: :ok

  def verify(project_id, capsule, maps) do
    with {:ok, data} <- Capsule.open(capsule),
         {:ok, actors} <- Records.resolve_actors(data["actors"]),
         policy_maps = Map.merge(maps, policy(data, project_id)),
         expected = expected_rows(data["rows"], project_id, actors, policy_maps),
         {:ok, actual} <- Records.capture(project_id, Map.values(maps["sessions"])) do
      if actual["rows"] == expected, do: :ok, else: {:error, :ideation_recovery_verification_failed}
    end
  end

  defp expected_rows(rows, project_id, actors, maps) do
    Map.new(rows, fn {collection, entries} ->
      {collection,
       entries
       |> Enum.map(fn entry ->
         collection
         |> Inventory.decode_row(entry)
         |> rewrite(collection, project_id, actors, maps)
         |> Map.put(:id, Map.fetch!(maps[collection], entry["id"]))
         |> then(&Inventory.encode_row(collection, &1))
       end)
       |> Enum.sort_by(& &1["id"])}
    end)
  end

  defp insert_records(rows, project_id, actors, policy) do
    maps =
      Enum.reduce(Inventory.tables(), policy, fn {collection, _table, _, _}, maps ->
        ids = Map.new(rows[collection], &insert_record(&1, collection, project_id, actors, maps))

        Map.put(maps, collection, ids)
      end)

    for entry <- rows["ideas"] do
      id = Map.fetch!(maps["ideas"], entry["id"])
      row = "ideas" |> Inventory.decode_row(entry) |> rewrite("ideas", project_id, actors, maps)

      Repo.update_all(from(i in "ideation_ideas", where: i.id == ^id),
        set: [source_idea_id: row.source_idea_id, canvas: row.canvas]
      )
    end

    maps
  end

  defp insert_record(entry, collection, project_id, actors, maps) do
    row = collection |> Inventory.decode_row(entry) |> rewrite(collection, project_id, actors, maps)
    row = if collection == "ideas", do: Map.put(row, :source_idea_id, nil), else: row
    {1, [%{id: id}]} = insert_row(collection, Map.delete(row, :id))
    {entry["id"], id}
  end

  # Literal table targets keep privileged write ownership statically auditable.
  defp insert_row("sessions", row), do: insert_one("ideation_sessions", row)
  defp insert_row("session_revisions", row), do: insert_one("ideation_session_revisions", row)
  defp insert_row("ideas", row), do: insert_one("ideation_ideas", row)
  defp insert_row("revisions", row), do: insert_one("ideation_idea_revisions", row)
  defp insert_row("edits", row), do: insert_one("ideation_idea_edits", row)
  defp insert_row("reveals", row), do: insert_one("ideation_reveal_operations", row)
  defp insert_row("publications", row), do: insert_one("ideation_idea_publications", row)

  defp insert_one(table, row), do: Repo.insert_all(table, [row], returning: [:id], log: false)
end
