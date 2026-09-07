defmodule StoryarnWeb.IdeationLive.Helpers.BoardData do
  @moduledoc false
  alias Storyarn.Ideation
  alias Storyarn.Projects

  @page_size 50
  @empty_counts %{active: 0, parked: 0, discarded: 0}

  def load(scope, project_id, session_id, filters) do
    with {:ok, project, membership} <- Projects.authorize(scope, project_id, :view),
         {:ok, sessions} <-
           Ideation.list_sessions(scope, project_id,
             status: filters.session_status,
             before_id: filters.session_before,
             limit: @page_size
           ),
         {:ok, content} <- session_content(scope, project_id, session_id, filters),
         {:ok, members} <- Projects.list_comment_members(scope, project_id) do
      can_edit = Projects.can?(membership.role, :edit_content)
      owner? = project.owner_id == scope.user.id

      {:ok,
       Map.merge(content, %{
         sessions: Enum.map(sessions, &session(&1, scope.user.id, can_edit, owner?)),
         sessions_next: next_cursor(sessions),
         session_before: filters.session_before,
         session_status: filters.session_status,
         can_edit: can_edit,
         is_owner: owner?,
         current_user_id: scope.user.id,
         members: members,
         can_manage: can_edit and content.session != nil and (owner? or content.session.facilitator_id == scope.user.id)
       })}
    end
  end

  def empty do
    %{
      sessions: [],
      sessions_next: nil,
      session_before: nil,
      session_status: :open,
      session: nil,
      session_missing: false,
      ideas: [],
      ideas_next: nil,
      idea_before: nil,
      counts: @empty_counts,
      can_edit: false,
      can_manage: false,
      is_owner: false,
      current_user_id: nil,
      members: []
    }
  end

  def session(value, actor_id, can_edit, owner?) do
    value
    |> Map.take([
      :id,
      :title,
      :objective,
      :context,
      :status,
      :revision,
      :configuration_version,
      :facilitator_id,
      :decision_owner_id,
      :deleted_at,
      :inserted_at
    ])
    |> Map.put(:configuration, Map.take(value.configuration, [:default_visibility, :publication_policy]))
    |> Map.put(:can_manage, can_edit and (owner? or value.facilitator_id == actor_id))
  end

  def page(rows), do: %{entries: rows, next: next_cursor(rows)}

  def idea(value) do
    # The facade chose the authorized revision before decrypting. Preview/search
    # must derive from that same projection, never from the persistence schema.
    Map.put(value, :preview, value.body |> Floki.parse_fragment!() |> Floki.text(sep: " "))
  end

  defp session_content(_scope, _project_id, nil, _filters), do: {:ok, Map.take(empty(), content_keys())}

  defp session_content(scope, project_id, session_id, filters) do
    case Ideation.get_session(scope, project_id, session_id) do
      {:ok, session} -> read_ideas(scope, project_id, session, filters)
      {:error, :not_found} -> {:ok, empty() |> Map.take(content_keys()) |> Map.put(:session_missing, true)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_ideas(scope, project_id, current, filters) do
    with {:ok, ideas} <-
           Ideation.list_ideas(scope, project_id, current.id,
             state: :all,
             before_id: filters.idea_before,
             limit: @page_size
           ),
         {:ok, counts} <- Ideation.count_ideas(scope, project_id, current.id) do
      {:ok,
       %{
         session: session(current, scope.user.id, false, false),
         session_missing: false,
         ideas: Enum.map(ideas, &idea/1),
         ideas_next: next_cursor(ideas),
         idea_before: filters.idea_before,
         counts: counts
       }}
    end
  end

  defp content_keys, do: [:session, :session_missing, :ideas, :ideas_next, :idea_before, :counts]
  defp next_cursor(rows) when length(rows) == @page_size, do: List.last(rows).id
  defp next_cursor(_), do: nil
end
