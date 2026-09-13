defmodule Storyarn.Ideation.Decisions.Queries.Sources do
  @moduledoc false

  alias Storyarn.Ideation.Decisions.Queries.Access
  alias Storyarn.Ideation.Decisions.Rules.Input
  alias Storyarn.Ideation.Groups
  alias Storyarn.Ideation.Ideas

  def preview(scope, project_id, session_id, selections) do
    with {:ok, _} <- Access.read(scope, project_id, session_id),
         {:ok, selections} <- Input.selections(selections),
         {:ok, rows} <- selected(session_id, selections),
         {:ok, _} <- Access.read(scope, project_id, session_id) do
      {:ok, Enum.map(rows, &public/1)}
    end
  end

  def search(scope, project_id, session_id, opts) do
    with {:ok, _} <- Access.read(scope, project_id, session_id),
         {:ok, page} <- Input.page(opts) do
      rows = search_rows(session_id, page)
      scanned = Enum.take(rows, 200)
      matched = Enum.filter(scanned, &matches?(&1, page.search))
      selected = Enum.take(matched, page.limit)

      cursor =
        cond do
          length(matched) > page.limit -> List.last(selected).id
          length(rows) > 200 -> List.last(scanned).id
          true -> nil
        end

      with {:ok, _} <- Access.read(scope, project_id, session_id) do
        {:ok, %{sources: Enum.map(selected, &public/1), next_cursor: cursor}}
      end
    end
  end

  def capture(session_id, selections, previous \\ nil) do
    current = current(session_id, selections)
    retained = retained(previous)

    with {:ok, rows} <- capture_rows(selections, current, retained) do
      sources = %{"items" => Enum.map(rows, &elem(&1, 0))}
      context = Map.new(rows, fn {source, context} -> {source["identity"], context} end)
      encoded = Jason.encode!(context)

      if byte_size(encoded) <= 256_000,
        do: {:ok, %{sources: sources, source_context: encoded}},
        else: {:error, :source_context_limit}
    end
  end

  defp retained(nil), do: %{}

  defp retained(previous) do
    context = Jason.decode!(previous.source_context)
    Map.new(previous.sources["items"], &{{&1["type"], &1["identity"], &1["version"]}, {&1, context[&1["identity"]]}})
  end

  defp capture_rows(selections, current, retained) do
    Enum.reduce_while(selections, {:ok, []}, fn selected, {:ok, rows} ->
      case capture_row(selected, current[{selected.type, selected.id}], retained) do
        {:ok, row} -> {:cont, {:ok, rows ++ [row]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp capture_row(_, nil, _), do: {:error, :sources_unavailable}

  defp capture_row(selected, row, retained) do
    previous = retained[{selected.type, selected.identity, selected.version}]

    cond do
      selected.identity != row.identity ->
        {:error, :sources_unavailable}

      previous != nil ->
        {source, context} = previous
        {:ok, {Map.put(source, "id", row.id), context}}

      selected.version != row.version ->
        {:error, :stale_sources}

      true ->
        {:ok, {metadata(row), %{"title" => row.title, "body" => row.body}}}
    end
  end

  def current(session_id, items) do
    idea_ids = for item <- items, type(item) == "idea", do: id(item)
    group_ids = for item <- items, type(item) == "group", do: id(item)

    rows =
      Ideas.decision_sources(session_id, Enum.uniq(idea_ids)) ++
        Groups.decision_sources(session_id, Enum.uniq(group_ids))

    Map.new(rows, &{{&1.type, &1.id}, &1})
  end

  def available?(source, current) do
    case current[{source["type"], source["id"]}] do
      %{identity: identity} -> identity == source["identity"]
      _ -> false
    end
  end

  defp selected(session_id, selections) do
    current = current(session_id, selections)

    selections
    |> Enum.reduce_while({:ok, []}, fn selected, {:ok, rows} ->
      row = current[{selected.type, selected.id}]

      cond do
        is_nil(row) -> {:halt, {:error, :sources_unavailable}}
        selected.identity != nil and selected.identity != row.identity -> {:halt, {:error, :sources_unavailable}}
        selected.version != nil and selected.version != row.version -> {:halt, {:error, :stale_sources}}
        true -> {:cont, {:ok, [row | rows]}}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      error -> error
    end
  end

  defp public(row), do: Map.merge(row, %{available: true, changed: false, current_version: row.version})

  defp metadata(row),
    do: Map.new([:type, :id, :identity, :version, :author_id], &{Atom.to_string(&1), Map.fetch!(row, &1)})

  defp type(item), do: Input.get(item, :type)
  defp id(item), do: Input.get(item, :id)
  defp search_rows(session_id, %{type: "idea"} = page), do: Ideas.search_decision_sources(session_id, page)
  defp search_rows(session_id, %{type: "group"} = page), do: Groups.search_decision_sources(session_id, page)
  defp matches?(_, ""), do: true

  defp matches?(row, search),
    do: String.contains?(String.downcase((row.title || "") <> " " <> (row.body || "")), search)
end
