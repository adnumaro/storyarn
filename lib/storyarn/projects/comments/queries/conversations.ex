defmodule Storyarn.Projects.Comments.Conversations do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Projects.Comments.Context
  alias Storyarn.Projects.Comments.IdeationConversations
  alias Storyarn.Projects.Comments.Mention
  alias Storyarn.Projects.Comments.Message
  alias Storyarn.Projects.Comments.Participation
  alias Storyarn.Projects.Comments.Projections.ProjectMembershipRecord
  alias Storyarn.Projects.Comments.Projections.WorkspaceMembershipRecord
  alias Storyarn.Projects.Comments.Queries
  alias Storyarn.Projects.Comments.Thread
  alias Storyarn.Projects.Project
  alias Storyarn.Repo

  @canonical_types ~w(flow_node flow_canvas sheet_canvas scene_canvas)
  @tools %{
    "flow" => ~w(flow_node flow_canvas),
    "sheet" => ~w(sheet_canvas),
    "scene" => ~w(scene_canvas),
    "brainstorming" => ~w(ideation_session ideation_idea ideation_group)
  }
  @max_id 9_223_372_036_854_775_807

  # Canonical conversations survive a vanished surface or context. Restricted
  # brainstorming sources enter through their current audience query instead.
  # Membership and source visibility precede search, counts and pagination.
  def readable_query(%{user: %{id: user_id}} = scope) do
    ideation_ids = from([thread: t] in IdeationConversations.readable_query(scope), select: t.id)

    direct =
      from(m in ProjectMembershipRecord,
        where: m.user_id == ^user_id and m.role in ~w(owner editor viewer),
        select: m.project_id
      )

    inherited =
      from(m in WorkspaceMembershipRecord,
        join: p in Project,
        on: p.workspace_id == m.workspace_id,
        where: m.user_id == ^user_id and m.role in ~w(owner admin member viewer),
        select: p.id
      )

    project_ids = union(direct, ^inherited)

    from(t in Thread,
      as: :thread,
      join: p in Project,
      as: :project,
      on: p.id == t.project_id,
      where: is_nil(p.deleted_at) and p.id in subquery(project_ids),
      where: t.source_type in ^@canonical_types or t.id in subquery(ideation_ids)
    )
  end

  def list(scope, opts) do
    with :ok <- validate_options(opts),
         {:ok, cursor} <- cursor(opts[:cursor]) do
      limit = min(opts[:limit] || 30, 100)

      rows =
        scope
        |> filtered_query(opts)
        |> filter_status(opts[:status])
        |> before_cursor(cursor)
        |> order_by([thread: t], desc: t.last_activity_at, desc: t.id)
        |> limit(^(limit + 1))
        |> Repo.all()

      page = Enum.take(rows, limit)
      last = List.last(page)
      next = if length(rows) > limit, do: %{at: DateTime.to_iso8601(last.last_activity_at), id: last.id}
      {:ok, page, next}
    end
  end

  # Counts describe the same authorized search, before the status tab and cursor.
  def counts(scope, opts) do
    rows =
      from([thread: t] in filtered_query(scope, opts), group_by: t.status, select: {t.status, count(t.id)})
      |> Repo.all()
      |> Map.new()

    open = Map.get(rows, "open", 0)
    resolved = Map.get(rows, "resolved", 0)
    %{all: open + resolved, open: open, resolved: resolved}
  end

  def metadata(_scope, []), do: %{}

  def metadata(scope, thread_ids) do
    from([thread: t, project: p] in readable_query(scope),
      join: w in assoc(p, :workspace),
      where: t.id in ^thread_ids,
      select:
        {t.id,
         %{
           project_id: p.id,
           project_name: p.name,
           project_slug: p.slug,
           workspace_id: w.id,
           workspace_name: w.name,
           workspace_slug: w.slug
         }}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp filtered_query(scope, opts) do
    scope
    |> readable_query()
    |> filter(:project_id, opts[:project_id])
    |> filter(:workspace_id, opts[:workspace_id])
    |> filter(:tool, opts[:tool])
    |> personal_filters(scope.user.id, opts)
    |> search(scope, opts[:search])
  end

  defp validate_options(opts) when is_list(opts) do
    if Keyword.keyword?(opts) and Enum.all?(opts, &valid_option?/1),
      do: :ok,
      else: {:error, :invalid_options}
  end

  defp validate_options(_), do: {:error, :invalid_options}

  defp valid_option?({key, value}) when key in [:project_id, :workspace_id, :limit],
    do: is_integer(value) and value > 0 and value <= @max_id

  defp valid_option?({key, value}) when key in [:following, :participated, :mentioned, :unread, :include_counts],
    do: is_boolean(value)

  defp valid_option?({:tool, value}), do: is_map_key(@tools, value)
  defp valid_option?({:status, value}), do: value in ~w(open resolved all)

  defp valid_option?({:search, value}),
    do: is_binary(value) and byte_size(value) <= 200 and String.valid?(value) and not String.contains?(value, <<0>>)

  defp valid_option?({:cursor, _}), do: true
  defp valid_option?(_), do: false

  defp filter(q, _, nil), do: q
  defp filter(q, :project_id, id), do: where(q, [thread: t], t.project_id == ^id)
  defp filter(q, :workspace_id, id), do: where(q, [project: p], p.workspace_id == ^id)
  defp filter(q, :tool, tool), do: where(q, [thread: t], t.source_type in ^Map.fetch!(@tools, tool))

  defp filter_status(q, value) when value in ~w(open resolved), do: where(q, [thread: t], t.status == ^value)
  defp filter_status(q, _), do: q

  defp personal_filters(q, user_id, opts) do
    q =
      from([thread: t] in q,
        left_join: p in Participation,
        as: :participation,
        on: p.thread_id == t.id and p.user_id == ^user_id
      )

    authored = from(m in Message, where: m.author_id == ^user_id, select: m.thread_id)

    mentioned =
      from(m in Message,
        join: mention in Mention,
        on: mention.message_id == m.id,
        where: mention.user_id == ^user_id,
        select: m.thread_id
      )

    q = if opts[:following] == true, do: where(q, [participation: p], p.following), else: q
    q = if opts[:participated] == true, do: where(q, [thread: t], t.id in subquery(authored)), else: q
    q = if opts[:mentioned] == true, do: where(q, [thread: t], t.id in subquery(mentioned)), else: q

    if opts[:unread] == true do
      unseen =
        from(m in Message,
          where:
            m.thread_id == parent_as(:thread).id and
              (is_nil(m.author_id) or m.author_id != ^user_id) and
              m.id > coalesce(parent_as(:participation).last_read_message_id, 0),
          select: 1
        )

      where(q, exists(subquery(unseen)))
    else
      q
    end
  end

  defp search(q, scope, text) when is_binary(text) and byte_size(text) > 0 do
    # Materialize authorized candidates once, before the expensive label branches.
    # Every source/context branch reads this relation, never all tenant threads.
    # Status and pagination remain outside it so counts retain their full scope.
    candidate_query = select(q, [thread: t], t)
    candidates = {"comment_search_candidates", Thread}
    candidate_ids = from(t in candidates, select: t.id)

    matching =
      from(m in Message,
        where: m.thread_id == parent_as(:thread).id,
        where: fragment("strpos(lower(?), lower(?)) > 0", m.body, ^text),
        select: 1
      )

    ideation =
      from([thread: t, comment_source: source] in IdeationConversations.readable_query(scope),
        where: t.id in subquery(candidate_ids),
        where: fragment("strpos(lower(?), lower(?)) > 0", source.name, ^text),
        select: t.id
      )

    sources = Queries.matching_source_threads(text, candidates)
    contexts = Context.matching_threads(text, candidates)

    with_cte(
      from(t in candidates,
        as: :thread,
        join: p in Project,
        as: :project,
        on: p.id == t.project_id,
        where:
          exists(subquery(matching)) or fragment("strpos(lower(?), lower(?)) > 0", p.name, ^text) or
            t.id in subquery(sources) or t.id in subquery(contexts) or t.id in subquery(ideation)
      ),
      "comment_search_candidates",
      materialized: true,
      as: ^candidate_query
    )
  end

  defp search(q, _scope, _), do: q
  defp cursor(nil), do: {:ok, nil}
  defp cursor(%{"at" => at, "id" => id}), do: cursor(%{at: at, id: id})

  defp cursor(%{at: at, id: id}) when is_binary(at) and is_integer(id) and id > 0 and id <= @max_id do
    case DateTime.from_iso8601(at) do
      {:ok, time, _} -> {:ok, {time, id}}
      _ -> {:error, :invalid_cursor}
    end
  end

  defp cursor(_), do: {:error, :invalid_cursor}
  defp before_cursor(q, nil), do: q

  defp before_cursor(q, {at, id}),
    do: where(q, [thread: t], t.last_activity_at < ^at or (t.last_activity_at == ^at and t.id < ^id))
end
