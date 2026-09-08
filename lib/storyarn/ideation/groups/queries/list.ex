defmodule Storyarn.Ideation.Groups.Queries.List do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Groups.Group
  alias Storyarn.Ideation.Groups.Membership
  alias Storyarn.Ideation.Groups.View
  alias Storyarn.Ideation.Ideas
  alias Storyarn.Ideation.Sessions
  alias Storyarn.Repo

  def run(scope, project_id, session_id) do
    with {:ok, _} <- Sessions.get_session(scope, project_id, session_id) do
      groups = Repo.all(from g in visible_query(session_id), order_by: g.id, limit: 501)
      if length(groups) <= 500, do: {:ok, project(groups, session_id)}, else: {:error, :group_limit_reached}
    end
  end

  def visible_query(session_id) do
    from g in Group,
      join: s in subquery(Sessions.canvas_settings_query()),
      on: s.id == g.session_id,
      where: g.session_id == ^session_id and is_nil(g.deleted_at) and not s.private_mode
  end

  def project(groups, session_id) do
    group_ids = Enum.map(groups, & &1.id)
    memberships = Repo.all(from m in Membership, where: m.group_id in ^group_ids and is_nil(m.removed_at))
    source_map = session_id |> Ideas.group_sources(Enum.map(memberships, & &1.idea_id)) |> Map.new(&{&1.idea_id, &1})
    by_group = Enum.group_by(memberships, & &1.group_id)

    Enum.map(groups, fn group ->
      members =
        for m <- Map.get(by_group, group.id, []),
            source = source_map[m.idea_id],
            source,
            do: %{source | source_revision: m.source_revision}

      View.group(group, Enum.sort_by(members, & &1.idea_id))
    end)
  end
end
