defmodule Storyarn.Ideation.Ideas.Execution.Connections do
  @moduledoc false
  import Ecto.Changeset, only: [change: 2]
  import Ecto.Query

  alias Storyarn.Ideation.Ideas.Execution.Transaction
  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Ideation.Ideas.Queries.Visible
  alias Storyarn.Ideation.Ideas.Rules.Input
  alias Storyarn.Repo

  # Every caller already holds the session contribution lock. Placement and
  # content have separate versions; changing either cannot invalidate link undo.
  def update(access, command) do
    ids = command.changes |> Enum.flat_map(&[&1.source_id, &1.target_id]) |> Enum.uniq()

    with :ok <- visible(access, ids) do
      sources = sources(access, Map.keys(command.versions))
      fingerprint = fingerprint(access, command)

      case replay(sources, command.request_key, fingerprint) do
        {:ok, response} -> Transaction.success(response)
        :new -> apply_changes(sources, command, fingerprint)
        error -> error
      end
    end
  end

  # The compatibility port also advances the link version and clears a previous
  # batch receipt, so it cannot silently defeat a later optimistic undo.
  def connect(access, source_id, target_id, connected?) do
    with :ok <- visible(access, [source_id, target_id]) do
      [source] = sources(access, [source_id])
      previous = Map.get(source.canvas, "links", [])
      links = set_link(previous, target_id, connected?)

      cond do
        previous == links ->
          Transaction.success(%{id: source_id})

        length(links) > 100 ->
          {:error, :invalid_canvas}

        true ->
          persist(source, links, Map.take(directions(source), Enum.map(links, &to_string/1)))
          Transaction.success(%{id: source_id}, audiences(source))
      end
    end
  end

  # Validate before creating anything. The target will have a fresh identity, so
  # appending it under the lock cannot overwrite another participant's link.
  def creation_sources(_access, []), do: {:ok, []}

  def creation_sources(access, ids) do
    with :ok <- visible(access, ids) do
      sources = sources(access, ids)

      if Enum.all?(sources, &(length(Map.get(&1.canvas, "links", [])) < 100)),
        do: {:ok, sources},
        else: {:error, :invalid_connections}
    end
  end

  def connect_creation(sources, target_id) do
    acknowledgements =
      sources
      |> Enum.map(fn source ->
        persist(
          source,
          Map.get(source.canvas, "links", []) ++ [target_id],
          Map.put(directions(source), to_string(target_id), "none")
        )

        %{id: source.id, before_version: version(source), version: version(source) + 1}
      end)
      |> Enum.sort_by(& &1.id)

    {acknowledgements, Enum.flat_map(sources, &audiences/1)}
  end

  defp apply_changes(sources, command, fingerprint) do
    if Enum.all?(sources, &(version(&1) == command.versions[&1.id])) do
      changes = Enum.group_by(command.changes, & &1.source_id)
      updates = Enum.map(sources, &prepare(&1, Map.fetch!(changes, &1.id)))

      if Enum.all?(updates, &(length(&1.links) <= 100)) do
        Enum.each(updates, &persist_update(&1, command.request_key, fingerprint))
        response = response(updates)
        Transaction.success(response, changed_audiences(updates))
      else
        {:error, :invalid_connections}
      end
    else
      {:error, :stale_connections}
    end
  end

  defp changed_audiences(updates) do
    for update <- updates, update.changes != [], audience <- audiences(update.source), do: audience
  end

  defp prepare(source, requested) do
    previous = Map.get(source.canvas, "links", [])

    changes =
      requested
      |> Enum.map(&acknowledge(source, &1))
      |> Enum.reject(&(&1.connected == &1.previous_connected and &1.direction == &1.previous_direction))

    links = Enum.reduce(changes, previous, &set_link(&2, &1.target_id, &1.connected))

    directions =
      Enum.reduce(changes, directions(source), fn change, directions ->
        key = to_string(change.target_id)
        if change.connected, do: Map.put(directions, key, change.direction), else: Map.delete(directions, key)
      end)

    %{
      source: source,
      changes: changes,
      links: links,
      directions: directions,
      version: version(source) + if(changes == [], do: 0, else: 1)
    }
  end

  defp acknowledge(source, change) do
    connected? = change.target_id in Map.get(source.canvas, "links", [])
    previous_direction = if connected?, do: Map.get(directions(source), to_string(change.target_id), "forward")
    direction = if change.connected, do: Map.get(change, :direction, previous_direction || "none")

    %{
      source_id: change.source_id,
      target_id: change.target_id,
      connected: change.connected,
      direction: direction,
      previous_connected: connected?,
      previous_direction: previous_direction
    }
  end

  defp persist_update(update, key, fingerprint) do
    receipt = %{
      "request_key" => key,
      "fingerprint" => fingerprint,
      "changes" => Enum.map(update.changes, &string_keys/1)
    }

    canvas =
      update.source.canvas
      |> Map.put("links", update.links)
      |> Map.put("link_directions", update.directions)
      |> Map.put("links_version", update.version)
      |> Map.put("links_receipt", receipt)

    update.source |> change(canvas: canvas) |> Repo.update!()
  end

  defp persist(source, links, directions) do
    canvas =
      source.canvas
      |> Map.put("links", links)
      |> Map.put("link_directions", directions)
      |> Map.put("links_version", version(source) + 1)
      |> Map.delete("links_receipt")

    source |> change(canvas: canvas) |> Repo.update!()
  end

  defp replay(sources, key, fingerprint) do
    matching = Enum.filter(sources, &(get_in(&1.canvas, ["links_receipt", "request_key"]) == key))

    cond do
      Enum.any?(matching, &(get_in(&1.canvas, ["links_receipt", "fingerprint"]) != fingerprint)) ->
        {:error, :idempotency_conflict}

      length(matching) == length(sources) ->
        updates =
          Enum.map(sources, fn source ->
            changes = Enum.map(source.canvas["links_receipt"]["changes"], &atom_keys/1)
            %{source: source, version: version(source), changes: changes}
          end)

        {:ok, response(updates)}

      matching != [] ->
        {:error, :stale_connections}

      true ->
        :new
    end
  end

  defp response(updates) do
    %{
      changes: updates |> Enum.flat_map(& &1.changes) |> Enum.sort_by(&{&1.source_id, &1.target_id}),
      versions: updates |> Enum.map(&%{id: &1.source.id, version: &1.version}) |> Enum.sort_by(& &1.id)
    }
  end

  defp fingerprint(access, command) do
    {:connections, access.user_id, command.changes, Enum.sort(command.versions)}
    |> Input.fingerprint()
    |> Base.encode64()
  end

  defp visible(access, ids) do
    readable = Visible.visible_link_ids(access.session_id, access.user_id, ids)
    if MapSet.new(readable) == MapSet.new(ids), do: :ok, else: {:error, :not_found}
  end

  defp sources(access, ids),
    do: Repo.all(from i in Idea, where: i.session_id == ^access.session_id and i.id in ^ids and is_nil(i.deleted_at))

  defp set_link(previous, target, true), do: Enum.uniq(previous ++ [target])
  defp set_link(previous, target, false), do: Enum.reject(previous, &(&1 == target))
  defp directions(source), do: Map.get(source.canvas, "link_directions", %{})
  defp version(source), do: Map.get(source.canvas, "links_version", 0)

  defp audiences(source) do
    if source.published_revision,
      do: Enum.reject([:shared, source.author_id], &is_nil/1),
      else: Enum.reject([source.author_id], &is_nil/1)
  end

  defp string_keys(change), do: Map.new(change, fn {key, value} -> {Atom.to_string(key), value} end)

  defp atom_keys(change) do
    connected? = change["connected"]

    %{
      source_id: change["source_id"],
      target_id: change["target_id"],
      connected: connected?,
      direction: Map.get(change, "direction", if(connected?, do: "forward")),
      previous_connected: Map.get(change, "previous_connected", not connected?),
      previous_direction: Map.get(change, "previous_direction", if(not connected?, do: "forward"))
    }
  end
end
