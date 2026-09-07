defmodule Storyarn.Ideation.Recovery.Restore do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Recovery.Capsule
  alias Storyarn.Ideation.Recovery.Inventory
  alias Storyarn.Ideation.Recovery.Records
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  def run(project_id, capsule) do
    if Repo.in_transaction?(), do: restore(project_id, capsule), else: {:error, :ideation_recovery_transaction_required}
  end

  defp restore(project_id, nil) do
    if Repo.exists?(from s in "ideation_sessions", where: s.project_id == ^project_id),
      do: {:error, :legacy_snapshot_excludes_ideation},
      else: {:ok, %{}}
  end

  defp restore(project_id, capsule) do
    with {:ok, data} <- Capsule.open(capsule),
         {:ok, actors} <- Records.resolve_actors(data["actors"]) do
      now = DateTime.to_naive(TimeHelpers.now())

      Repo.update_all(from(s in "ideation_sessions", where: s.project_id == ^project_id and is_nil(s.deleted_at)),
        set: [deleted_at: now]
      )

      maps = insert_records(data["rows"], project_id, actors, recovery_policy(data, project_id))
      with :ok <- verify(project_id, capsule, maps), do: {:ok, maps}
    end
  end

  def verify(_project_id, nil, maps) when map_size(maps) == 0, do: :ok

  def verify(project_id, capsule, maps) do
    with {:ok, data} <- Capsule.open(capsule),
         {:ok, actors} <- Records.resolve_actors(data["actors"]),
         policy_maps = Map.merge(maps, recovery_policy(data, project_id)),
         expected = expected_rows(data["rows"], project_id, actors, policy_maps),
         {:ok, actual} <- Records.capture(project_id, Map.values(maps["sessions"])) do
      if actual["rows"] == expected, do: :ok, else: {:error, :ideation_recovery_verification_failed}
    end
  end

  defp expected_rows(rows, project_id, actors, maps) do
    Map.new(rows, fn {collection, entries} ->
      {collection,
       Enum.map(entries, fn entry ->
         collection
         |> Inventory.decode_row(entry)
         |> rewrite(collection, project_id, actors, maps)
         |> Map.put(:id, Map.fetch!(maps[collection], entry["id"]))
         |> then(&Inventory.encode_row(collection, &1))
       end)}
    end)
  end

  defp insert_records(rows, project_id, actors, policy) do
    maps =
      Enum.reduce(Inventory.tables(), policy, fn {collection, _table, _, _}, maps ->
        ids = Map.new(rows[collection], &insert_record(&1, collection, project_id, actors, maps))

        Map.put(maps, collection, ids)
      end)

    for entry <- rows["ideas"], source = entry["source_idea_id"], not is_nil(source) do
      id = Map.fetch!(maps["ideas"], entry["id"])
      source_id = Map.fetch!(maps["ideas"], source)
      Repo.update_all(from(i in "ideation_ideas", where: i.id == ^id), set: [source_idea_id: source_id])
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

  defp rewrite(row, collection, project_id, actors, maps) do
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

  defp recovery_policy(data, project_id) do
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
