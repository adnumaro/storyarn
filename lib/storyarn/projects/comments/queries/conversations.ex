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
    "brainstorming" => ~w(ideation_session ideation_idea ideation_group ideation_decision)
  }
  @tool_of Map.new(for {tool, types} <- @tools, type <- types, do: {type, tool})
  @max_id 9_223_372_036_854_775_807
  @max_priority 3

  # 2 when a message by someone else is beyond the reader's watermark, +1 when
  # the reader is mentioned; evaluated on the personal-state joins below.
  defmacrop priority_expr(participation, others, mentioned) do
    quote do
      fragment(
        "(CASE WHEN COALESCE(?, 0) > COALESCE(?, 0) THEN 2 ELSE 0 END) + (CASE WHEN COALESCE(?, 0) > 0 THEN 1 ELSE 0 END)",
        unquote(others).max_id,
        unquote(participation).last_read_message_id,
        unquote(mentioned).hit
      )
    end
  end

  # Facet predicates over the same joins; a gate is open unless its toggle is active.
  defmacrop unread_expr(participation, others) do
    quote do
      fragment("COALESCE(?, 0) > COALESCE(?, 0)", unquote(others).max_id, unquote(participation).last_read_message_id)
    end
  end

  defmacrop following_expr(participation),
    do: quote(do: fragment("COALESCE(?, false)", unquote(participation).following))

  defmacrop hit_expr(binding), do: quote(do: fragment("COALESCE(?, 0) > 0", unquote(binding).hit))

  defmacrop gate(active, predicate),
    do: quote(do: fragment("(NOT ?::boolean OR ?)", ^unquote(active), unquote(predicate)))

  defmacrop facet(predicate, first_gate, second_gate) do
    quote do
      count(
        fragment("CASE WHEN ? AND ? AND ? THEN 1 END", unquote(predicate), unquote(first_gate), unquote(second_gate))
      )
    end
  end

  defmacrop facet(predicate, first_gate, second_gate, third_gate) do
    quote do
      count(
        fragment(
          "CASE WHEN ? AND ? AND ? AND ? THEN 1 END",
          unquote(predicate),
          unquote(first_gate),
          unquote(second_gate),
          unquote(third_gate)
        )
      )
    end
  end

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

  # Unread conversations and those mentioning the reader lead; the rest follow
  # by activity. The cursor carries that priority so pages stay stable.
  def list(scope, opts) do
    with :ok <- validate_options(opts),
         {:ok, cursor} <- cursor(opts[:cursor]) do
      limit = min(opts[:limit] || 30, 100)

      rows =
        scope
        |> filtered_query(opts)
        |> filter_status(opts[:status])
        |> with_personal_state(scope.user.id)
        |> before_cursor(cursor)
        |> order_by([thread: t, participation: p, others: o, mentioned: mt],
          desc: priority_expr(p, o, mt),
          desc: t.last_activity_at,
          desc: t.id
        )
        |> select([thread: t, participation: p, others: o, mentioned: mt], %{
          thread: t,
          priority: priority_expr(p, o, mt)
        })
        |> limit(^(limit + 1))
        |> Repo.all()

      page = Enum.take(rows, limit)
      last = List.last(page)
      priorities = Map.new(page, &{&1.thread.id, &1.priority})

      next =
        if length(rows) > limit,
          do: %{prio: last.priority, at: DateTime.to_iso8601(last.thread.last_activity_at), id: last.thread.id}

      {:ok, Enum.map(page, & &1.thread), next, priorities}
    end
  end

  # Every chip counts the rows it would show if it were the one selected with
  # the other filters kept; each group ignores only its own selection.
  def counts(scope, opts) do
    user_id = scope.user.id
    scoped = scoped_query(scope, opts)
    unread_on = opts[:unread] == true
    following_on = opts[:following] == true
    participated_on = opts[:participated] == true
    mentioned_on = opts[:mentioned] == true

    by_tool_status =
      scoped
      |> personal_filters(user_id, opts)
      |> search(scope, opts[:search])
      |> group_by([thread: t], [t.source_type, t.status])
      |> select([thread: t], {t.source_type, t.status, count(t.id)})
      |> Repo.all()

    personal =
      scoped
      |> filter(:tool, opts[:tool])
      |> filter_status(opts[:status])
      |> search(scope, opts[:search])
      |> with_personal_state(user_id)
      |> select([participation: p, others: o, mentioned: mt, authored: a], %{
        unread:
          facet(
            unread_expr(p, o),
            gate(following_on, following_expr(p)),
            gate(participated_on, hit_expr(a)),
            gate(mentioned_on, hit_expr(mt))
          ),
        following:
          facet(
            following_expr(p),
            gate(unread_on, unread_expr(p, o)),
            gate(participated_on, hit_expr(a)),
            gate(mentioned_on, hit_expr(mt))
          ),
        participated: facet(hit_expr(a), gate(unread_on, unread_expr(p, o)), gate(following_on, following_expr(p))),
        mentioned: facet(hit_expr(mt), gate(unread_on, unread_expr(p, o)), gate(following_on, following_expr(p)))
      })
      |> Repo.one()

    selected_types = if opts[:tool], do: Map.fetch!(@tools, opts[:tool]), else: Map.keys(@tool_of)
    selected_statuses = if opts[:status] in ~w(open resolved), do: [opts[:status]], else: ~w(open resolved)
    open = sum_counts(by_tool_status, &(elem(&1, 0) in selected_types and elem(&1, 1) == "open"))
    resolved = sum_counts(by_tool_status, &(elem(&1, 0) in selected_types and elem(&1, 1) == "resolved"))

    tools =
      by_tool_status
      |> Enum.filter(&(elem(&1, 1) in selected_statuses))
      |> Enum.reduce(Map.new(Map.keys(@tools), &{&1, 0}), fn {type, _status, count}, acc ->
        Map.update(acc, @tool_of[type], count, &(&1 + count))
      end)

    Map.merge(
      %{all: tools |> Map.values() |> Enum.sum(), open: open, resolved: resolved, tools: tools},
      personal || %{unread: 0, mentioned: 0, participated: 0, following: 0}
    )
  end

  defp sum_counts(rows, keep?), do: rows |> Enum.filter(keep?) |> Enum.map(&elem(&1, 2)) |> Enum.sum()

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

  defp scoped_query(scope, opts) do
    scope
    |> readable_query()
    |> filter(:project_id, opts[:project_id])
    |> filter(:workspace_id, opts[:workspace_id])
  end

  # Personal toggles narrow the candidates before search materializes them, so
  # the label branches only scan rows the reader would see anyway.
  defp filtered_query(scope, opts) do
    scope
    |> scoped_query(opts)
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

  # Personal toggles narrow the rows; they read the participation row under
  # its own alias so the ordering joins below can add theirs independently.
  defp personal_filters(q, user_id, opts) do
    q =
      from([thread: t] in q,
        left_join: p in Participation,
        as: :read_state,
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

    q = if opts[:following] == true, do: where(q, [read_state: p], p.following), else: q
    q = if opts[:participated] == true, do: where(q, [thread: t], t.id in subquery(authored)), else: q
    q = if opts[:mentioned] == true, do: where(q, [thread: t], t.id in subquery(mentioned)), else: q

    if opts[:unread] == true do
      unseen =
        from(m in Message,
          where:
            m.thread_id == parent_as(:thread).id and
              (is_nil(m.author_id) or m.author_id != ^user_id) and
              m.id > coalesce(parent_as(:read_state).last_read_message_id, 0),
          select: 1
        )

      where(q, exists(subquery(unseen)))
    else
      q
    end
  end

  # One correlated read per row of the reader's watermark, the newest message
  # by someone else, whether they were mentioned and whether they wrote here.
  defp with_personal_state(q, user_id) do
    others =
      from(m in Message,
        where: m.thread_id == parent_as(:thread).id and (is_nil(m.author_id) or m.author_id != ^user_id),
        select: %{max_id: max(m.id)}
      )

    mentioned =
      from(m in Message,
        join: mention in Mention,
        on: mention.message_id == m.id,
        where: m.thread_id == parent_as(:thread).id and mention.user_id == ^user_id,
        select: %{hit: count(m.id)}
      )

    authored =
      from(m in Message,
        where: m.thread_id == parent_as(:thread).id and m.author_id == ^user_id,
        select: %{hit: count(m.id)}
      )

    from([thread: t] in q,
      left_join: p in Participation,
      as: :participation,
      on: p.thread_id == t.id and p.user_id == ^user_id,
      left_lateral_join: o in subquery(others),
      as: :others,
      on: true,
      left_lateral_join: mt in subquery(mentioned),
      as: :mentioned,
      on: true,
      left_lateral_join: a in subquery(authored),
      as: :authored,
      on: true
    )
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
  defp cursor(%{"prio" => prio, "at" => at, "id" => id}), do: cursor(%{prio: prio, at: at, id: id})

  defp cursor(%{prio: prio, at: at, id: id})
       when is_integer(prio) and prio >= 0 and prio <= @max_priority and is_binary(at) and is_integer(id) and id > 0 and
              id <= @max_id do
    case DateTime.from_iso8601(at) do
      {:ok, time, _} -> {:ok, {prio, time, id}}
      _ -> {:error, :invalid_cursor}
    end
  end

  defp cursor(_), do: {:error, :invalid_cursor}
  defp before_cursor(q, nil), do: q

  defp before_cursor(q, {prio, at, id}) do
    where(
      q,
      [thread: t, participation: p, others: o, mentioned: mt],
      priority_expr(p, o, mt) < ^prio or
        (priority_expr(p, o, mt) == ^prio and
           (t.last_activity_at < ^at or (t.last_activity_at == ^at and t.id < ^id)))
    )
  end
end
