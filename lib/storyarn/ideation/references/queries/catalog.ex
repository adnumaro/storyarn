defmodule Storyarn.Ideation.References.Catalog do
  @moduledoc false
  import Ecto.Query
  import Storyarn.Ideation.References.Input, only: [valid_id: 1]

  alias Storyarn.Ideation.References.Input
  alias Storyarn.Ideation.References.Queries.Targets
  alias Storyarn.Ideation.References.Reference
  alias Storyarn.Ideation.References.Revision
  alias Storyarn.Ideation.References.Source
  alias Storyarn.Ideation.References.View
  alias Storyarn.Repo

  def list(scope, project_id, session_id, idea_id, opts) do
    with {:ok, _} <- Source.get(scope, project_id, session_id, idea_id),
         {:ok, page} <- Input.page(opts) do
      rows = session_id |> session_query(idea_id) |> paginate(page) |> Repo.all()
      selected = Enum.take(rows, page.limit)

      with {:ok, targets} <- Targets.get_many(scope, project_id, target_ids(selected)),
           {:ok, _} <- Source.get(scope, project_id, session_id, idea_id) do
        {:ok,
         %{
           references: Enum.map(selected, &View.project(&1, targets[{&1.target_type, &1.target_id}])),
           next_cursor: if(length(rows) > page.limit, do: List.last(selected).id)
         }}
      end
    end
  end

  def search(scope, project_id, session_id, idea_id, opts) when is_list(opts) do
    with true <- Keyword.keyword?(opts),
         {:ok, _} <- Source.get(scope, project_id, session_id, idea_id),
         {:ok, targets} <- Targets.search(scope, project_id, opts[:type], opts[:search] || "", limit: 20),
         {:ok, _} <- Source.get(scope, project_id, session_id, idea_id) do
      {:ok, targets}
    else
      false -> {:error, :invalid_reference}
      {:error, _} = error -> error
    end
  end

  def search(_, _, _, _, _), do: {:error, :invalid_reference}

  def get(scope, project_id, session_id, idea_id, id) do
    with {:ok, _} <- Source.get(scope, project_id, session_id, idea_id),
         %Reference{} = reference <- record(session_id, idea_id, id),
         {:ok, targets} <- Targets.get_many(scope, project_id, target_ids([reference])),
         {:ok, _} <- Source.get(scope, project_id, session_id, idea_id) do
      {:ok, View.project(reference, targets[{reference.target_type, reference.target_id}])}
    else
      nil -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def history(scope, project_id, session_id, idea_id, id) do
    with {:ok, _} <- Source.get(scope, project_id, session_id, idea_id),
         %Reference{} = reference <- record(session_id, idea_id, id) do
      revisions =
        Repo.all(from r in Revision, where: r.reference_id == ^reference.id, order_by: [desc: r.number], limit: 50)

      # Authorize after loading historical text; never return stored previews
      # when either side has become inaccessible during the read.
      with {:ok, target} <- Targets.get(scope, project_id, reference.target_type, reference.target_id),
           true <- View.available?(reference, target),
           {:ok, _} <- Source.get(scope, project_id, session_id, idea_id) do
        {:ok, Enum.map(revisions, &View.revision/1)}
      else
        _ -> {:error, :not_found}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  def backlinks(scope, project_id, type, target_id, opts) do
    with {:ok, page} <- Input.page(opts),
         {:ok, target} <- Targets.get(scope, project_id, type, target_id) do
      query =
        from(r in Reference,
          where: r.target_type == ^type and r.target_id == ^target_id and r.target_identity == ^target.identity,
          where: is_nil(r.deleted_at)
        )
        |> Source.readable(project_id)
        |> paginate(page)

      rows = Repo.all(query)

      with {:ok, current} <- Targets.get(scope, project_id, type, target_id),
           true <- current.identity == target.identity do
        # Re-read source audience after target authorization, before exposing
        # session labels or a count to another tool.
        ids = Enum.map(rows, & &1.reference.id)

        readable =
          Reference |> where([r], r.id in ^ids and is_nil(r.deleted_at)) |> Source.readable(project_id) |> Repo.all()

        visible = Map.new(readable, &{&1.reference.id, &1})
        # Do not promote the lookahead row when a source loses visibility:
        # the next cursor still belongs to the original, fixed page.
        selected = rows |> Enum.take(page.limit) |> Enum.filter(&Map.has_key?(visible, &1.reference.id))

        {:ok,
         %{
           references:
             Enum.map(selected, fn row ->
               r = visible[row.reference.id].reference

               %{
                 id: r.id,
                 session_id: r.session_id,
                 idea_id: r.idea_id,
                 relation: r.relation,
                 session_name: visible[r.id].session_name
               }
             end),
           next_cursor: if(length(rows) > page.limit, do: Enum.at(rows, page.limit - 1).reference.id)
         }}
      else
        _ -> {:error, :not_found}
      end
    end
  end

  def record(session_id, idea_id, id) when valid_id(id),
    do: Repo.one(from r in session_query(session_id, idea_id), where: r.id == ^id)

  def record(_, _, _), do: nil

  def session_query(session_id, idea_id) do
    query = from r in Reference, where: r.session_id == ^session_id and is_nil(r.deleted_at)
    if is_nil(idea_id), do: where(query, [r], is_nil(r.idea_id)), else: where(query, [r], r.idea_id == ^idea_id)
  end

  defp paginate(query, page) do
    query = if page.before_id, do: where(query, [r], r.id < ^page.before_id), else: query
    from r in query, order_by: [desc: r.id], limit: ^(page.limit + 1)
  end

  defp target_ids(rows), do: for(row <- rows, not is_nil(row.target_id), do: {row.target_type, row.target_id})
end
