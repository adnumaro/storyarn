defmodule StoryarnWeb.IdeationLive.Handlers.CommentHandlers do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]

  alias Storyarn.Ideation
  alias Storyarn.Projects
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.IdeationLive.Helpers.Params

  def init(socket) do
    assign(socket, :comments, %{
      open: false,
      presentation: "canvas",
      pins: [],
      draftPosition: nil,
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
      decisionId: nil,
      decisionCounts: %{},
      context: Ecto.UUID.generate()
    })
  end

  def close(socket), do: socket |> init() |> refresh()

  # A decision's discussion follows the decision shown in the panel: it opens on
  # the newest thread about it, or on a composer that starts one.
  def follow_decision(%{assigns: %{comments: %{open: true, decisionId: id}}} = socket, id) when is_integer(id),
    do: socket

  def follow_decision(%{assigns: %{comments: %{decisionId: id}}} = socket, nil) when is_integer(id), do: close(socket)
  def follow_decision(socket, nil), do: socket

  def follow_decision(socket, decision_id) do
    socket
    |> init()
    |> put(%{open: true, presentation: "workspace", decisionId: decision_id})
    |> refresh()
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

  defp dispatch(action, params, socket) when action in ~w(create reply set_status move place) do
    Authorize.with_authorization(socket, :comment, &mutate(action, params, &1), fn current, _ ->
      failure(init(current), :not_found)
    end)
  end

  defp dispatch("open", params, socket) do
    with {:ok, idea_id} <- Params.optional_id(params["idea_id"]),
         {:ok, group_id} <- Params.optional_id(params["group_id"]),
         {:ok, position} <- position(params),
         true <- is_nil(idea_id) or is_nil(group_id) do
      socket =
        socket
        |> init()
        |> put(%{open: true, ideaId: idea_id, groupId: group_id, draftPosition: position})
        |> refresh()

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

  defp dispatch("close", _, socket), do: {:noreply, close(socket)}
  defp dispatch("select_thread", params, socket), do: {:noreply, select(socket, positive(params["thread_id"]))}

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

  def refresh(socket) do
    socket = if socket.assigns.comments.open, do: load_context(socket), else: socket

    socket =
      case socket.assigns.comments do
        %{open: true, thread: %{id: id}} -> detail(socket, id)
        %{open: true, decisionId: id} when is_integer(id) -> newest_discussion(socket)
        _ -> socket
      end

    refresh_pins(socket)
  end

  defp newest_discussion(socket) do
    %{current_scope: scope, project: project, session_id: session_id, comments: state} = socket.assigns

    case Projects.list_ideation_comment_threads(scope, project.id, session_id, {:decision, state.decisionId}, limit: 1) do
      {:ok, %{threads: [%{id: id} | _]}} -> detail(socket, id)
      _ -> socket
    end
  end

  defp refresh_pins(socket) do
    %{current_scope: scope, project: project, session_id: session_id} = socket.assigns

    pins =
      case Projects.list_ideation_comment_pins(scope, project.id, session_id) do
        {:ok, pins} -> pins
        _ -> []
      end

    # Discussions about decisions are not placed on the canvas; their cards count them.
    {discussions, pins} = Enum.split_with(pins, &(&1.source.type == "ideation_decision"))

    put(socket, %{
      pins: pins,
      decisionCounts:
        discussions
        |> Enum.group_by(& &1.source.id, & &1.message_count)
        |> Map.new(fn {id, counts} -> {id, Enum.sum(counts)} end),
      canComment: match?({:ok, _, _}, Projects.authorize(scope, project.id, :comment))
    })
  end

  def refresh_participation(%{assigns: %{comments: %{open: true} = state}} = socket, thread_id) do
    if match?(%{id: ^thread_id}, state.thread),
      do: refresh(socket),
      else: socket
  end

  def refresh_participation(socket, _thread_id), do: socket

  def linked(socket, %{"thread" => id}), do: select(socket, positive(id))
  def linked(socket, _), do: socket

  defp mutate("place", params, socket) do
    with %{open: true, thread: nil, canComment: true, decisionId: nil} <- socket.assigns.comments,
         {:ok, position} <- position(params) do
      {:reply, %{ok: true}, put(socket, %{draftPosition: position})}
    else
      _ -> failure(socket, :not_found)
    end
  end

  defp mutate("create", params, socket) do
    %{current_scope: scope, project: project, session_id: session_id, comments: state} = socket.assigns

    scope
    |> Projects.create_ideation_comment(
      project.id,
      session_id,
      anchor(state),
      params
      |> Map.take(~w(body client_request_id mention_user_ids position))
      |> Map.put_new("position", state.draftPosition)
    )
    |> result(socket)
  end

  defp mutate("move", params, socket) do
    id = positive(params["thread_id"])

    with {:ok, _} <- current_thread(socket, id),
         {:ok, position} <- position(params),
         {:ok, thread} <-
           Projects.move_comment_thread(
             socket.assigns.current_scope,
             socket.assigns.project.id,
             id,
             position,
             positive(params["expected_revision"])
           ) do
      {:reply, %{ok: true, thread: thread}, refresh(socket)}
    else
      {:error, reason} -> failure(refresh(socket), reason)
    end
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

  defp result({:ok, %{thread: %{id: id}}}, socket), do: {:reply, %{ok: true}, socket |> select(id) |> refresh_pins()}
  defp result({:error, reason}, socket), do: failure(refresh(socket), reason)

  defp select(socket, id) do
    case current_thread(socket, id) do
      {:ok, %{thread: %{source: source}}} ->
        state = socket.assigns.comments
        idea_id = if source.type == "ideation_idea", do: source.id
        group_id = if source.type == "ideation_group", do: source.id
        decision_id = if source.type == "ideation_decision", do: source.id

        context =
          if {idea_id, group_id, decision_id} == {state.ideaId, state.groupId, state.decisionId},
            do: state.context,
            else: Ecto.UUID.generate()

        socket
        |> put(%{
          open: true,
          presentation: presentation(decision_id, state.presentation),
          ideaId: idea_id,
          groupId: group_id,
          decisionId: decision_id,
          context: context,
          thread: nil,
          draftPosition: if(context == socket.assigns.comments.context, do: socket.assigns.comments.draftPosition),
          messages: [],
          error: nil
        })
        |> load_context()
        |> detail(id)

      _ ->
        init(socket)
    end
  end

  defp load_context(socket) do
    %{current_scope: scope, project: project, session_id: id, comments: state} = socket.assigns

    source =
      cond do
        state.decisionId -> Ideation.decision_comment_source(scope, project.id, id, state.decisionId)
        state.groupId -> Ideation.group_comment_source(scope, project.id, id, state.groupId)
        true -> Ideation.comment_source(scope, project.id, id, state.ideaId)
      end

    case source do
      {:ok, _source} ->
        put(socket, %{
          canComment: match?({:ok, _, _}, Projects.authorize(scope, project.id, :comment)),
          members: members(scope, project.id),
          selectedSourceId: state.decisionId || state.groupId || state.ideaId || id,
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
           type in ~w(ideation_session ideation_idea ideation_group ideation_decision) and
             session_id == socket.assigns.session_id do
      {:ok, detail}
    else
      _ -> {:error, :not_found}
    end
  end

  defp anchor(%{decisionId: id}) when is_integer(id), do: {:decision, id}
  defp anchor(%{groupId: id}) when is_integer(id), do: {:group, id}
  defp anchor(state), do: state.ideaId

  defp presentation(decision_id, _current) when is_integer(decision_id), do: "workspace"
  defp presentation(nil, "workspace"), do: "canvas"
  defp presentation(nil, current), do: current

  defp position(%{"position" => %{"x" => x, "y" => y}})
       when is_number(x) and is_number(y) and abs(x) <= 10_000_000 and abs(y) <= 10_000_000, do: {:ok, %{x: x, y: y}}

  defp position(params) when not is_map_key(params, "position"), do: {:ok, %{x: 0, y: 0}}
  defp position(_), do: {:error, :invalid_position}

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
