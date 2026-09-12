defmodule Storyarn.Ideation.References.ContextualCatalog do
  @moduledoc false
  import Ecto.Query
  import Storyarn.Ideation.References.Input, only: [valid_id: 1]

  alias Storyarn.Ideation.References.ContextualInput
  alias Storyarn.Ideation.References.Queries.Targets
  alias Storyarn.Ideation.References.Reference
  alias Storyarn.Ideation.References.Source
  alias Storyarn.Ideation.References.View
  alias Storyarn.Ideation.Sessions
  alias Storyarn.Platform.Shared.SearchHelpers
  alias Storyarn.Repo

  def get(scope, project_id, type, id, opts) do
    with :ok <- ContextualInput.target(type, id),
         {:ok, page} <- ContextualInput.page(opts),
         {:ok, target} <- Targets.get(scope, project_id, type, id) do
      linked = linked_rows(project_id, target, page)
      available = available_rows(project_id, target, page)

      with {:ok, current} <- Targets.get(scope, project_id, type, id),
           true <- current.identity == target.identity do
        {:ok,
         %{
           target: current,
           linked_sessions: linked_views(project_id, current, Enum.take(linked, page.limit)),
           available_sessions: available_views(project_id, current, Enum.take(available, page.limit)),
           linked_next_cursor: next_cursor(linked, page.limit, & &1.reference.session_id),
           available_next_cursor: next_cursor(available, page.limit, & &1.id)
         }}
      else
        _ -> {:error, :not_found}
      end
    end
  end

  def resume(scope, project_id, type, id, session_id) when valid_id(session_id) do
    with :ok <- ContextualInput.target(type, id),
         {:ok, session} <- Sessions.get_session(scope, project_id, session_id),
         {:ok, target} <- Targets.get(scope, project_id, type, id),
         %Reference{} = reference <- existing(project_id, session_id, target),
         {:ok, _} <- Source.get(scope, project_id, session_id, nil),
         {:ok, current} <- Targets.get(scope, project_id, type, id),
         true <- View.available?(reference, current),
         %Reference{} = current_reference <- existing(project_id, session_id, current) do
      {:ok, %{session: session, reference: View.project(current_reference, current)}}
    else
      _ -> {:error, :not_found}
    end
  end

  def resume(_, _, _, _, _), do: {:error, :not_found}

  def existing(project_id, session_id, target) do
    project_id
    |> linked_query(target)
    |> where([r], r.session_id == ^session_id)
    |> order_by([r], asc: fragment("CASE WHEN ? = 'origin' THEN 0 ELSE 1 END", r.relation), desc: r.id)
    |> limit(1)
    |> Repo.one()
    |> case do
      %{reference: reference} -> reference
      nil -> nil
    end
  end

  defp linked_rows(project_id, target, page) do
    query =
      project_id
      |> linked_query(target)
      |> distinct([r], desc: r.session_id)
      |> order_by([r],
        desc: r.session_id,
        asc: fragment("CASE WHEN ? = 'origin' THEN 0 ELSE 1 END", r.relation),
        desc: r.id
      )
      |> limit(^(page.limit + 1))

    query = if page.linked_before_id, do: where(query, [r], r.session_id < ^page.linked_before_id), else: query
    Repo.all(query)
  end

  defp linked_views(project_id, target, selected) do
    ids = Enum.map(selected, & &1.reference.id)

    # Recheck source visibility after target authorization. Never promote a
    # lookahead row when the original page loses a source during the read.
    visible =
      project_id
      |> linked_query(target)
      |> where([r], r.id in ^ids)
      |> Repo.all()
      |> Map.new(&{&1.reference.id, &1})

    for row <- selected, current = visible[row.reference.id], not is_nil(current) do
      %{
        id: current.reference.session_id,
        title: current.session_name,
        status: current.session_status,
        reference: View.project(current.reference, target)
      }
    end
  end

  defp available_rows(project_id, target, page) do
    linked = project_id |> linked_query(target) |> exclude(:select) |> select([r], r.session_id)
    pattern = "%#{SearchHelpers.sanitize_like_query(page.search)}%"

    query =
      from(s in subquery(Sessions.contextual_session_choices_query()),
        where: s.project_id == ^project_id and s.status == :open,
        where: s.id not in subquery(linked) and ilike(s.name, ^pattern),
        order_by: [desc: s.id],
        limit: ^(page.limit + 1),
        select: %{id: s.id, title: s.name, status: s.status}
      )

    query = if page.available_before_id, do: where(query, [s], s.id < ^page.available_before_id), else: query
    Repo.all(query)
  end

  defp available_views(project_id, target, selected) do
    ids = Enum.map(selected, & &1.id)
    linked = project_id |> linked_query(target) |> exclude(:select) |> select([r], r.session_id)

    visible =
      from(s in subquery(Sessions.contextual_session_choices_query()),
        where: s.project_id == ^project_id and s.status == :open and s.id in ^ids,
        where: s.id not in subquery(linked),
        select: %{id: s.id, title: s.name, status: s.status}
      )
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    for row <- selected, current = visible[row.id], not is_nil(current), do: current
  end

  defp linked_query(project_id, target) do
    from(r in Reference,
      join: s in subquery(Sessions.contextual_session_choices_query()),
      on: s.id == r.session_id,
      where: s.project_id == ^project_id,
      where: r.target_type == ^target.type and r.target_id == ^target.id and r.target_identity == ^target.identity,
      where: is_nil(r.deleted_at) and is_nil(r.idea_id),
      select: %{reference: r, session_name: s.name, session_status: s.status}
    )
  end

  defp next_cursor(rows, limit, getter), do: if(length(rows) > limit, do: getter.(Enum.at(rows, limit - 1)))
end
