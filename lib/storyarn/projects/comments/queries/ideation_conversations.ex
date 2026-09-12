defmodule Storyarn.Projects.Comments.IdeationConversations do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation
  alias Storyarn.Projects.Comments.Mention
  alias Storyarn.Projects.Comments.Message
  alias Storyarn.Projects.Comments.Participation
  alias Storyarn.Projects.Comments.Projections.ProjectMembershipRecord
  alias Storyarn.Projects.Comments.Projections.WorkspaceMembershipRecord
  alias Storyarn.Projects.Comments.Thread
  alias Storyarn.Projects.Project
  alias Storyarn.Repo

  @types ~w(ideation_session ideation_idea ideation_group)
  @max_id 9_223_372_036_854_775_807

  def member_ids(project_id) do
    direct = from(m in ProjectMembershipRecord, where: m.project_id == ^project_id, select: m.user_id)

    inherited =
      from(m in WorkspaceMembershipRecord,
        join: p in Project,
        on: p.workspace_id == m.workspace_id,
        where: p.id == ^project_id,
        select: m.user_id
      )

    direct |> union(^inherited) |> Repo.all()
  end

  def readable_query(%{user: %{id: user_id}}) do
    sources =
      "ideation_session"
      |> Ideation.comment_sources_query()
      |> union_all(^Ideation.comment_sources_query("ideation_idea"))
      |> union_all(^Ideation.comment_sources_query("ideation_group"))

    from(t in Thread,
      as: :thread,
      join: s in subquery(sources),
      on:
        s.project_id == t.project_id and s.session_id == t.ideation_session_id and
          s.session_id == t.container_id and s.source_type == t.source_type and s.id == t.source_id and
          s.recovery_identity == t.source_recovery_identity
    )
    |> with_project_access(user_id)
    |> with_anchor_pointer()
  end

  defp with_project_access(query, user_id) do
    from([thread: t] in query,
      join: p in Project,
      as: :project,
      on: p.id == t.project_id,
      left_join: pm in ProjectMembershipRecord,
      on: pm.project_id == p.id and pm.user_id == ^user_id,
      left_join: wm in WorkspaceMembershipRecord,
      on: wm.workspace_id == p.workspace_id and wm.user_id == ^user_id,
      where: is_nil(p.deleted_at) and (not is_nil(pm.id) or not is_nil(wm.id))
    )
  end

  defp with_anchor_pointer(query) do
    from([thread: t] in query,
      where:
        t.source_type == "ideation_session" or
          (t.source_type == "ideation_idea" and t.ideation_idea_id == t.source_id) or
          (t.source_type == "ideation_group" and t.ideation_group_id == t.source_id)
    )
  end

  def restricted_message_ids do
    from(m in Message, join: t in Thread, on: t.id == m.thread_id, where: t.source_type in ^@types, select: m.id)
  end

  def readable_message_ids(scope) do
    from([thread: t] in readable_query(scope), join: m in Message, on: m.thread_id == t.id, select: m.id)
  end

  def destinations(_scope, []), do: %{}

  def destinations(scope, message_ids) do
    from([thread: t, project: p] in readable_query(scope),
      join: w in assoc(p, :workspace),
      join: m in Message,
      on: m.thread_id == t.id,
      where: m.id in ^message_ids,
      select:
        {{p.id, m.id},
         %{
           surface: "brainstorming",
           project_id: p.id,
           project_slug: p.slug,
           workspace_slug: w.slug,
           session_id: t.container_id,
           thread_id: t.id
         }}
    )
    |> Repo.all()
    |> Map.new()
  end

  # Contract for the future Hub: authorized and paginated before previews are
  # materialized, independent of membership in or participation in a thread.
  def list(scope, opts) do
    with :ok <- validate_options(opts),
         {:ok, cursor} <- cursor(opts[:cursor]) do
      limit = if is_integer(opts[:limit]) and opts[:limit] > 0, do: min(opts[:limit], 100), else: 30

      query =
        scope
        |> readable_query()
        |> filter(:project_id, opts[:project_id])
        |> filter(:workspace_id, opts[:workspace_id])
        |> filter(:session_id, opts[:session_id])
        |> filter(:source_type, opts[:source_type])
        |> filter(:status, opts[:status])
        |> personal_filters(scope.user.id, opts)
        |> search(opts[:search])
        |> before_cursor(cursor)
        |> order_by([thread: t], desc: t.last_activity_at, desc: t.id)
        |> limit(^(limit + 1))

      rows = Repo.all(query)
      page = Enum.take(rows, limit)

      next =
        if length(rows) > limit, do: %{at: DateTime.to_iso8601(List.last(page).last_activity_at), id: List.last(page).id}

      {:ok, page, next}
    end
  end

  defp validate_options(opts) when is_list(opts) do
    if Keyword.keyword?(opts) and Enum.all?(opts, &valid_option?/1),
      do: :ok,
      else: {:error, :invalid_options}
  end

  defp validate_options(_), do: {:error, :invalid_options}

  defp valid_option?({key, value}) when key in [:project_id, :workspace_id, :session_id, :limit],
    do: is_integer(value) and value > 0 and value <= @max_id

  defp valid_option?({key, value}) when key in [:following, :participated, :mentioned, :unread], do: is_boolean(value)

  defp valid_option?({:source_type, value}), do: value in @types
  defp valid_option?({:status, value}), do: value in ~w(open resolved all)
  defp valid_option?({:search, value}), do: is_binary(value) and byte_size(value) <= 200
  defp valid_option?({:cursor, _}), do: true
  defp valid_option?(_), do: false

  defp filter(q, _, nil), do: q
  defp filter(q, :project_id, id), do: where(q, [thread: t], t.project_id == ^id)
  defp filter(q, :workspace_id, id), do: where(q, [project: p], p.workspace_id == ^id)
  defp filter(q, :session_id, id), do: where(q, [thread: t], t.container_id == ^id)
  defp filter(q, :source_type, value), do: where(q, [thread: t], t.source_type == ^value)
  defp filter(q, :status, value) when value in ~w(open resolved), do: where(q, [thread: t], t.status == ^value)
  defp filter(q, _, _), do: q

  defp personal_filters(q, user_id, opts) do
    q =
      from([thread: t] in q,
        left_join: p in Participation,
        as: :participation,
        on: p.thread_id == t.id and p.user_id == ^user_id
      )

    q = if opts[:following] == true, do: where(q, [participation: p], p.following), else: q
    authored = from(m in Message, where: m.author_id == ^user_id, select: m.thread_id)

    mentioned =
      from(m in Message,
        join: mention in Mention,
        on: mention.message_id == m.id,
        where: mention.user_id == ^user_id,
        select: m.thread_id
      )

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

  defp search(q, text) when is_binary(text) and byte_size(text) in 1..200 do
    matching = from(m in Message, where: fragment("strpos(lower(?), lower(?)) > 0", m.body, ^text), select: m.thread_id)
    where(q, [thread: t], t.id in subquery(matching))
  end

  defp search(q, _), do: q
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
