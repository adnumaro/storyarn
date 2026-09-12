defmodule Storyarn.Projects.Comments.ParticipationState do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Projects.Access
  alias Storyarn.Projects.Comments.Message
  alias Storyarn.Projects.Comments.Participation
  alias Storyarn.Projects.Comments.Payload
  alias Storyarn.Projects.Comments.Queries
  alias Storyarn.Repo

  def update(scope, project_id, thread_id, action) do
    if Repo.in_transaction?() do
      {:error, :comment_requires_outer_transaction}
    else
      Repo.transaction(fn -> update_locked(scope, project_id, thread_id, action) end)
    end
  end

  defp update_locked(scope, project_id, thread_id, action) do
    with true <- Payload.valid_id?(thread_id),
         {:ok, _, _} <- Access.authorize_locked(scope, project_id, :view),
         thread when not is_nil(thread) <- Queries.thread(project_id, thread_id),
         true <- Queries.ideation?(thread),
         source when not is_nil(source) <- Queries.available_source(thread, scope: scope, lock: :share) do
      thread = Queries.thread(project_id, thread_id, lock: :update) || Repo.rollback(:not_found)
      write(thread, scope.user.id, action)
      thread
    else
      _ -> Repo.rollback(:not_found)
    end
  end

  defp write(thread, user_id, {:follow, following}) when is_boolean(following) do
    Repo.insert_all(Participation, [%{thread_id: thread.id, user_id: user_id, following: following}],
      on_conflict: [set: [following: following]],
      conflict_target: [:thread_id, :user_id]
    )
  end

  defp write(thread, user_id, {:read, message_id}) do
    message = if Payload.valid_id?(message_id), do: Queries.message(thread.project_id, message_id)
    if is_nil(message) or message.thread_id != thread.id, do: Repo.rollback(:invalid_message)
    # Serialize against replies and other tabs. A delayed acknowledgement may
    # advance only through a message the client actually received, never regress.
    current = Repo.get_by(Participation, thread_id: thread.id, user_id: user_id)
    watermark = max(message_id, if(current, do: current.last_read_message_id, else: 0))

    Repo.insert_all(Participation, [%{thread_id: thread.id, user_id: user_id, last_read_message_id: watermark}],
      on_conflict: [set: [last_read_message_id: watermark]],
      conflict_target: [:thread_id, :user_id]
    )
  end

  defp write(_, _, _), do: Repo.rollback(:invalid_request)

  def followers(thread_id) do
    Repo.all(from(p in Participation, where: p.thread_id == ^thread_id and p.following, select: p.user_id))
  end

  def decorate(dtos, %{user: %{id: user_id}}) do
    ids =
      for %{source: %{type: type}, id: id} <- dtos, type in ~w(ideation_session ideation_idea ideation_group), do: id

    decorate_ideation(dtos, ids, user_id)
  end

  def decorate(dtos, _), do: dtos
  defp decorate_ideation(dtos, [], _user_id), do: dtos

  defp decorate_ideation(dtos, ids, user_id) do
    states =
      from(p in Participation, where: p.thread_id in ^ids and p.user_id == ^user_id)
      |> Repo.all()
      |> Map.new(&{&1.thread_id, &1})

    latest =
      from(m in Message, where: m.thread_id in ^ids, group_by: m.thread_id, select: {m.thread_id, max(m.id)})
      |> Repo.all()
      |> Map.new()

    others =
      from(m in Message,
        where: m.thread_id in ^ids and (is_nil(m.author_id) or m.author_id != ^user_id),
        group_by: m.thread_id,
        select: {m.thread_id, max(m.id)}
      )
      |> Repo.all()
      |> Map.new()

    Enum.map(dtos, fn dto ->
      if dto.id in ids do
        state = states[dto.id]

        Map.merge(dto, %{
          following: state != nil and state.following,
          unread: Map.get(others, dto.id, 0) > if(state, do: state.last_read_message_id, else: 0),
          last_message_id: latest[dto.id]
        })
      else
        dto
      end
    end)
  end
end
