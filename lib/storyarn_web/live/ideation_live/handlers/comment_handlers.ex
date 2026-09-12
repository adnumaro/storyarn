defmodule StoryarnWeb.IdeationLive.Handlers.CommentHandlers do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]

  alias Storyarn.Projects
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.IdeationLive.Helpers.Params

  def init(socket) do
    assign(socket, :comments, %{
      open: false,
      presentation: "workspace",
      threads: [],
      nextCursor: nil,
      thread: nil,
      messages: [],
      messageNextCursor: nil,
      members: [],
      canComment: false,
      selectedSourceId: nil,
      selectedSourceLabel: nil,
      statusFilter: "open",
      error: nil,
      ideaId: nil,
      groupId: nil,
      context: Ecto.UUID.generate()
    })
  end

  def handle(action, params, socket) do
    with true <- socket.assigns.session_id != nil,
         true <- params["epoch"] == socket.assigns.epoch,
         {:ok, id} <- Params.positive(params["session_id"]),
         true <- id == socket.assigns.session_id,
         true <- action == "open" or params["comment_context"] == socket.assigns.comments.context do
      dispatch(action, params, socket)
    else
      _ -> failure(refresh(socket), :not_found)
    end
  end

  defp dispatch(action, params, socket) when action in ~w(create reply set_status) do
    Authorize.with_authorization(socket, :edit_content, &mutate(action, params, &1), fn current, _ ->
      failure(init(current), :not_found)
    end)
  end

  defp dispatch("open", params, socket) do
    with {:ok, idea_id} <- Params.optional_id(params["idea_id"]),
         {:ok, group_id} <- Params.optional_id(params["group_id"]),
         true <- is_nil(idea_id) or is_nil(group_id) do
      socket = socket |> init() |> put(%{open: true, ideaId: idea_id, groupId: group_id}) |> refresh()
      {:reply, %{ok: socket.assigns.comments.open}, socket}
    else
      _ ->
        failure(socket, :not_found)
    end
  end

  defp dispatch(action, params, socket) when action in ~w(follow read) do
    Authorize.with_authorization(
      socket,
      :manage_comment_state,
      &personal_state(action, params, &1),
      fn current, _ -> failure(init(current), :not_found) end
    )
  end

  defp dispatch("close", _, socket), do: {:noreply, init(socket)}
  defp dispatch("select_thread", params, socket), do: {:noreply, select(socket, positive(params["thread_id"]))}

  defp dispatch("filter", params, socket) do
    status = if params["status"] in ~w(open resolved all), do: params["status"], else: "open"
    {:noreply, socket |> put(%{statusFilter: status}) |> refresh()}
  end

  defp dispatch("load_more", _, socket), do: {:noreply, load_threads(socket, socket.assigns.comments.nextCursor)}

  defp dispatch("load_messages", _, socket) do
    case socket.assigns.comments do
      %{thread: %{id: id}, messageNextCursor: cursor} when not is_nil(cursor) ->
        {:noreply, detail(socket, id, cursor)}

      _ ->
        {:noreply, socket}
    end
  end

  defp dispatch(_, _, socket), do: failure(socket, :not_found)

  defp personal_state(action, params, socket) do
    id = positive(params["thread_id"])

    case current_thread(socket, id) do
      {:ok, _} ->
        %{current_scope: scope, project: project} = socket.assigns

        response =
          if action == "follow",
            do: Projects.set_ideation_comment_following(scope, project.id, id, params["following"]),
            else: Projects.mark_ideation_comment_read(scope, project.id, id, positive(params["message_id"]))

        result(response, socket)

      _ ->
        failure(refresh(socket), :not_found)
    end
  end

  def refresh(%{assigns: %{comments: %{open: false}}} = socket), do: socket

  def refresh(socket) do
    socket = load_threads(socket)

    if socket.assigns.comments.open && socket.assigns.comments.thread,
      do: detail(socket, socket.assigns.comments.thread.id),
      else: socket
  end

  def refresh_participation(%{assigns: %{comments: %{open: true} = state}} = socket, thread_id) do
    if Enum.any?(state.threads, &(&1.id == thread_id)) or match?(%{id: ^thread_id}, state.thread),
      do: refresh(socket),
      else: socket
  end

  def refresh_participation(socket, _thread_id), do: socket

  def linked(socket, %{"thread" => id}), do: select(socket, positive(id))
  def linked(socket, _), do: socket

  defp mutate("create", params, socket) do
    %{current_scope: scope, project: project, session_id: session_id, comments: state} = socket.assigns

    scope
    |> Projects.create_ideation_comment(
      project.id,
      session_id,
      anchor(state),
      Map.take(params, ~w(body client_request_id mention_user_ids))
    )
    |> result(socket)
  end

  defp mutate("reply", params, socket) do
    id = positive(params["thread_id"])

    case current_thread(socket, id) do
      {:ok, _} ->
        socket.assigns.current_scope
        |> Projects.reply_to_comment_thread(
          socket.assigns.project.id,
          id,
          Map.take(params, ~w(body parent_id client_request_id mention_user_ids))
        )
        |> result(socket)

      _ ->
        failure(refresh(socket), :not_found)
    end
  end

  defp mutate("set_status", params, socket) do
    id = positive(params["thread_id"])

    with {:ok, _} <- current_thread(socket, id),
         {:ok, _} <-
           Projects.set_comment_thread_status(
             socket.assigns.current_scope,
             socket.assigns.project.id,
             id,
             params["status"],
             positive(params["expected_revision"])
           ) do
      {:reply, %{ok: true}, select(socket, id)}
    else
      {:error, reason} -> failure(refresh(socket), reason)
    end
  end

  defp result({:ok, %{thread: %{id: id}}}, socket), do: {:reply, %{ok: true}, select(socket, id)}
  defp result({:error, reason}, socket), do: failure(refresh(socket), reason)

  defp select(socket, id) do
    case current_thread(socket, id) do
      {:ok, %{thread: %{source: source}}} ->
        idea_id = if source.type == "ideation_idea", do: source.id
        group_id = if source.type == "ideation_group", do: source.id

        context =
          if idea_id == socket.assigns.comments.ideaId and group_id == socket.assigns.comments.groupId,
            do: socket.assigns.comments.context,
            else: Ecto.UUID.generate()

        socket
        |> put(%{
          open: true,
          ideaId: idea_id,
          groupId: group_id,
          context: context,
          thread: nil,
          messages: [],
          error: nil
        })
        |> load_threads()
        |> detail(id)

      _ ->
        init(socket)
    end
  end

  defp load_threads(socket, cursor \\ nil) do
    %{current_scope: scope, project: project, session_id: id, comments: state} = socket.assigns

    case Projects.list_ideation_comment_threads(scope, project.id, id, anchor(state),
           status: state.statusFilter,
           cursor: cursor
         ) do
      {:ok, %{threads: threads, next_cursor: next}} ->
        threads = if cursor, do: Enum.uniq_by(state.threads ++ threads, & &1.id), else: threads

        put(socket, %{
          threads: threads,
          nextCursor: next,
          canComment: match?({:ok, _, _}, Projects.authorize(scope, project.id, :edit_content)),
          members: members(scope, project.id),
          selectedSourceId: state.groupId || state.ideaId || id,
          selectedSourceLabel: nil
        })

      _ ->
        init(socket)
    end
  end

  defp detail(socket, id, cursor \\ nil) do
    case current_thread(socket, id, cursor: cursor) do
      {:ok, %{thread: thread, messages: messages, next_cursor: next}} ->
        messages = if cursor, do: Enum.uniq_by(messages ++ socket.assigns.comments.messages, & &1.id), else: messages
        thread = Map.put(thread, :last_message_id, messages |> Enum.map(& &1.id) |> Enum.max(fn -> 0 end))
        put(socket, %{thread: thread, messages: messages, messageNextCursor: next})

      _ ->
        init(socket)
    end
  end

  defp current_thread(socket, id, opts \\ []) do
    with {:ok, %{thread: %{source: %{type: type, session_id: session_id}}} = detail} <-
           Projects.get_comment_thread(socket.assigns.current_scope, socket.assigns.project.id, id, opts),
         true <-
           type in ["ideation_session", "ideation_idea", "ideation_group"] and session_id == socket.assigns.session_id do
      {:ok, detail}
    else
      _ -> {:error, :not_found}
    end
  end

  defp anchor(%{groupId: id}) when is_integer(id), do: {:group, id}
  defp anchor(state), do: state.ideaId

  defp members(scope, project_id) do
    case Projects.list_comment_members(scope, project_id) do
      {:ok, members} -> members
      _ -> []
    end
  end

  defp positive(id) do
    case Params.positive(id) do
      {:ok, id} -> id
      _ -> nil
    end
  end

  defp put(socket, values), do: assign(socket, :comments, Map.merge(socket.assigns.comments, values))

  defp failure(socket, reason) do
    message = if reason == :stale, do: "stale", else: "unavailable"
    {:reply, %{ok: false, error: message}, put(socket, %{error: message})}
  end
end
