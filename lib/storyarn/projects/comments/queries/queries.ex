defmodule Storyarn.Projects.Comments.Queries do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Projects.Comments.Mention
  alias Storyarn.Projects.Comments.Message
  alias Storyarn.Projects.Comments.Projections.FlowNodeRecord
  alias Storyarn.Projects.Comments.Projections.FlowRecord
  alias Storyarn.Projects.Comments.Projections.ProjectMembershipRecord
  alias Storyarn.Projects.Comments.Projections.UserRecord
  alias Storyarn.Projects.Comments.Projections.WorkspaceMembershipRecord
  alias Storyarn.Projects.Comments.Thread
  alias Storyarn.Projects.Project
  alias Storyarn.Repo

  def thread(project_id, thread_id, opts \\ []) do
    query = from(t in Thread, where: t.project_id == ^project_id and t.id == ^thread_id)
    query |> maybe_lock(opts) |> Repo.one()
  end

  def source(project_id, flow_id, node_id, opts \\ []) do
    flow_query = from(f in FlowRecord, where: f.id == ^flow_id and f.project_id == ^project_id and is_nil(f.deleted_at))

    case flow_query |> maybe_lock(opts) |> Repo.one() do
      %FlowRecord{} ->
        from(n in FlowNodeRecord, where: n.id == ^node_id and n.flow_id == ^flow_id and is_nil(n.deleted_at))
        |> maybe_lock(opts)
        |> Repo.one()

      _ ->
        nil
    end
  end

  def source_available?(%Thread{flow_node_id: nil}), do: false

  def source_available?(thread) do
    case source(thread.project_id, thread.container_id, thread.flow_node_id) do
      %FlowNodeRecord{id: id, inserted_at: inserted_at} ->
        id == thread.source_id and inserted_at == thread.source_inserted_at

      _ ->
        false
    end
  end

  def available_sources(threads) do
    ids = Enum.map(threads, & &1.id)

    from(t in Thread,
      join: n in FlowNodeRecord,
      on: t.flow_node_id == n.id and t.source_id == n.id and t.source_inserted_at == n.inserted_at,
      join: f in FlowRecord,
      on: f.id == n.flow_id and f.id == t.container_id and f.project_id == t.project_id,
      where: t.id in ^ids and is_nil(n.deleted_at) and is_nil(f.deleted_at),
      select: {t.id, n}
    )
    |> Repo.all()
    |> Map.new()
  end

  def list_threads(project_id, flow_id, opts) do
    query = from(t in Thread, where: t.project_id == ^project_id and t.container_id == ^flow_id)
    query = if opts[:node_id], do: where(query, [t], t.source_id == ^opts[:node_id]), else: query
    query = if opts[:status] in ["open", "resolved"], do: where(query, [t], t.status == ^opts[:status]), else: query
    query = if cursor(opts), do: where(query, [t], t.id < ^cursor(opts)), else: query
    page(query, opts)
  end

  def list_messages(thread_id, opts) do
    query = from(m in Message, where: m.thread_id == ^thread_id)
    query = if cursor(opts), do: where(query, [m], m.id < ^cursor(opts)), else: query
    {messages, next_cursor} = page(query, opts)
    {Enum.reverse(messages), next_cursor}
  end

  def root_messages(thread_ids) do
    from(m in Message,
      where: m.thread_id in ^thread_ids and is_nil(m.parent_id),
      select: {m.thread_id, m}
    )
    |> Repo.all()
    |> Map.new()
  end

  def message(project_id, message_id) do
    Repo.one(from(m in Message, where: m.id == ^message_id and m.project_id == ^project_id))
  end

  def destinations(_user_id, []), do: []

  def destinations(user_id, message_ids) do
    Repo.all(
      from([m, t, n, f] in destination_sources(message_ids),
        join: p in Project,
        on: p.id == t.project_id,
        join: w in assoc(p, :workspace),
        left_join: pm in ProjectMembershipRecord,
        on: pm.project_id == p.id and pm.user_id == ^user_id,
        left_join: wm in WorkspaceMembershipRecord,
        on: wm.workspace_id == p.workspace_id and wm.user_id == ^user_id,
        where: is_nil(p.deleted_at),
        where: not is_nil(pm.id) or not is_nil(wm.id),
        select: %{
          message_id: m.id,
          project_role: pm.role,
          workspace_role: wm.role,
          destination: %{
            project_id: p.id,
            project_slug: p.slug,
            workspace_slug: w.slug,
            flow_id: f.id,
            node_id: n.id,
            thread_id: t.id
          }
        }
      )
    )
  end

  defp destination_sources(message_ids) do
    from(m in Message,
      join: t in Thread,
      on: t.id == m.thread_id and t.project_id == m.project_id,
      join: n in FlowNodeRecord,
      on: t.flow_node_id == n.id and t.source_id == n.id and t.source_inserted_at == n.inserted_at,
      join: f in FlowRecord,
      on: f.id == n.flow_id and f.id == t.container_id and f.project_id == t.project_id,
      where: m.id in ^message_ids and is_nil(f.deleted_at) and is_nil(n.deleted_at)
    )
  end

  def existing_request(project_id, author_id, request_id) do
    Repo.get_by(Message, project_id: project_id, author_id: author_id, client_request_id: request_id)
  end

  def authors(ids) do
    from(u in UserRecord, where: u.id in ^Enum.reject(ids, &is_nil/1))
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  def mentions(message_ids) do
    from(m in Mention, where: m.message_id in ^message_ids)
    |> Repo.all()
    |> Enum.group_by(& &1.message_id, & &1.user_id)
  end

  def members(project) do
    direct = from(m in ProjectMembershipRecord, where: m.project_id == ^project.id, select: m.user_id)
    inherited = from(m in WorkspaceMembershipRecord, where: m.workspace_id == ^project.workspace_id, select: m.user_id)

    Repo.all(
      from(u in UserRecord,
        where: u.id in subquery(direct) or u.id in subquery(inherited),
        order_by: [asc: u.display_name, asc: u.id]
      )
    )
  end

  def open_counts(project_id, flow_id) do
    from(t in Thread,
      join: n in FlowNodeRecord,
      on: t.flow_node_id == n.id and t.source_id == n.id and t.source_inserted_at == n.inserted_at,
      join: f in FlowRecord,
      on: f.id == n.flow_id,
      where: t.project_id == ^project_id and t.container_id == ^flow_id and t.status == "open",
      where: f.project_id == ^project_id and f.id == ^flow_id and is_nil(f.deleted_at) and is_nil(n.deleted_at),
      group_by: t.source_id,
      select: {t.source_id, count(t.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp maybe_lock(query, opts) do
    case opts[:lock] do
      :update -> lock(query, "FOR UPDATE")
      :share -> lock(query, "FOR SHARE")
      _ -> query
    end
  end

  defp page(query, opts) do
    limit =
      case opts[:limit] do
        n when is_integer(n) and n > 0 -> min(n, 100)
        _ -> 30
      end

    rows = Repo.all(from(row in query, order_by: [desc: row.id], limit: ^(limit + 1)))
    page = Enum.take(rows, limit)
    next_cursor = if length(rows) > limit, do: List.last(page).id
    {page, next_cursor}
  end

  defp cursor(opts) do
    case opts[:cursor] do
      id when is_integer(id) and id > 0 -> id
      _ -> nil
    end
  end
end
