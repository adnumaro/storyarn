defmodule Storyarn.Ideation.Recovery.Records do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Recovery.Inventory
  alias Storyarn.Repo

  def capture(project_id, session_ids \\ nil) do
    {rows, _bytes, _count} =
      Enum.reduce(Inventory.tables(), {%{}, 0, 0}, fn {collection, table, parent, fields}, {rows, bytes, count} ->
        ids = parent_ids(parent, project_id, rows)
        query = from row in table, where: field(row, ^parent) in ^ids, order_by: row.id, select: map(row, ^fields)

        query =
          if collection == "sessions" and is_list(session_ids),
            do: where(query, [row], row.id in ^session_ids),
            else: query

        {entries, bytes, count} = read_pages(query, collection, 0, [], bytes, count)
        {Map.put(rows, collection, entries), bytes, count}
      end)

    actor_ids = actor_ids(rows)
    actors = Repo.all(from u in "users", where: u.id in ^actor_ids, select: {u.id, type(u.recovery_identity, Ecto.UUID)})

    {:ok,
     %{
       "format" => "storyarn.ideation",
       "version" => 1,
       "actors" => Map.new(actors, fn {id, identity} -> {Integer.to_string(id), identity} end),
       "rows" =>
         Map.new(rows, fn {collection, entries} ->
           {collection, Enum.map(entries, &Inventory.encode_row(collection, &1))}
         end)
     }}
  catch
    :ideation_recovery_too_large -> {:error, :ideation_recovery_too_large}
  end

  def resolve_actors(actors) do
    identities = Map.values(actors)

    query =
      from u in "users",
        where: type(u.recovery_identity, Ecto.UUID) in ^identities,
        order_by: u.id,
        select: {type(u.recovery_identity, Ecto.UUID), u.id}

    locked = query |> lock("FOR KEY SHARE SKIP LOCKED") |> Repo.all() |> Map.new()
    existing = query |> Repo.all() |> Map.new()

    if MapSet.new(Map.keys(existing)) == MapSet.new(Map.keys(locked)) do
      {:ok, Map.new(actors, fn {id, identity} -> {String.to_integer(id), locked[identity]} end)}
    else
      {:error, :ideation_recovery_actors_busy}
    end
  end

  defp read_pages(query, collection, cursor, pages, bytes, count) do
    entries = query |> where([row], row.id > ^cursor) |> limit(100) |> Repo.all()
    page_bytes = Enum.sum(Enum.map(entries, &(collection |> Inventory.encode_row(&1) |> Jason.encode!() |> byte_size())))
    bytes = bytes + page_bytes
    count = count + length(entries)
    if bytes > Inventory.max_bytes() or count > Inventory.max_rows(), do: throw(:ideation_recovery_too_large)

    case entries do
      [] -> {pages |> Enum.reverse() |> List.flatten(), bytes, count}
      _ -> read_pages(query, collection, List.last(entries).id, [entries | pages], bytes, count)
    end
  end

  defp parent_ids(:project_id, project_id, _), do: [project_id]
  defp parent_ids(:session_id, _, rows), do: Enum.map(rows["sessions"], & &1.id)
  defp parent_ids(:idea_id, _, rows), do: Enum.map(rows["ideas"], & &1.id)

  defp actor_ids(rows) do
    direct =
      for {_, entries} <- rows,
          row <- entries,
          field <- Inventory.actor_fields(),
          id = row[field],
          is_integer(id),
          do: id

    historical =
      for row <- rows["session_revisions"],
          field <- ~w(facilitator_id decision_owner_id),
          id = row.snapshot[field],
          is_integer(id),
          do: id

    Enum.uniq(direct ++ historical)
  end
end
