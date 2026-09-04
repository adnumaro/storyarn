defmodule StoryarnWeb.SceneLive.Handlers.CommentHandlers do
  @moduledoc false

  use Gettext, backend: Storyarn.Gettext

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [connected?: 1, push_event: 3]

  alias Storyarn.Projects
  alias StoryarnWeb.Helpers.Authorize

  @mutations ~w(create reply set_status mode place move)

  def init(socket) do
    socket
    |> assign(:comments, empty_state())
    |> assign(:comment_pins, [])
    |> assign(:comment_focus_thread_id, nil)
  end

  def loaded(%{assigns: %{compact: true}} = socket), do: socket

  def loaded(socket) do
    if connected?(socket) do
      Projects.subscribe_scene_comments(socket.assigns.current_scope, socket.assigns.project.id, socket.assigns.scene.id)
    end

    refresh(socket)
  end

  def unload(socket) do
    if socket.assigns[:scene] do
      Projects.unsubscribe_scene_comments(socket.assigns.project.id, socket.assigns.scene.id)
    end

    socket
  end

  def close(%{assigns: %{comments: _state}} = socket) do
    socket
    |> put_state(%{open: false, placing: false, draftPosition: nil, draftId: nil, error: nil})
    |> assign(:comment_focus_thread_id, nil)
  end

  def close(socket), do: socket

  def handle_params(%{assigns: %{compact: true}} = socket, _params), do: socket
  def handle_params(%{assigns: %{scene: nil}} = socket, _params), do: socket

  def handle_params(socket, %{"thread" => thread_id}) do
    open_linked_thread(socket, positive_id(thread_id))
  end

  def handle_params(socket, _params), do: socket

  def handle(_action, _params, %{assigns: %{compact: true}} = socket), do: failure(socket, :unavailable)
  def handle(_action, _params, %{assigns: %{scene: nil}} = socket), do: failure(socket, :unavailable)

  def handle(action, params, socket) when action in @mutations do
    Authorize.with_authorization(
      socket,
      :edit_content,
      &mutate(action, params, &1),
      fn current, _reason -> failure(clear(current), :unauthorized) end
    )
  end

  def handle("open", _params, socket) do
    with {:ok, _project, _membership} <- authorize_read(socket),
         true <- not is_nil(socket.assigns.scene) do
      socket =
        socket
        |> put_state(%{
          open: true,
          presentation: "panel",
          placing: false,
          draftPosition: nil,
          draftId: nil,
          thread: nil,
          messages: [],
          messageNextCursor: nil,
          error: nil
        })
        |> assign(:right_panel, nil)
        |> assign(:comment_focus_thread_id, nil)
        |> refresh()

      {:reply, %{ok: true}, socket}
    else
      _error -> failure(clear(socket), :not_found)
    end
  end

  def handle("close", _params, socket), do: {:noreply, close(socket)}

  def handle("select_thread", params, socket) do
    presentation = if params["presentation"] == "canvas", do: "canvas", else: "panel"
    socket = put_state(socket, %{presentation: presentation})
    {:noreply, select_thread(socket, positive_id(params["thread_id"]))}
  end

  def handle("filter", params, socket) do
    status = if params["status"] in ~w(open resolved all), do: params["status"], else: "open"
    {:noreply, socket |> put_state(%{statusFilter: status, error: nil}) |> refresh()}
  end

  def handle("load_more", _params, socket) do
    case socket.assigns.comments.nextCursor do
      nil -> {:noreply, socket}
      cursor -> {:noreply, load_threads(socket, cursor)}
    end
  end

  def handle("load_messages", _params, socket) do
    case socket.assigns.comments do
      %{thread: %{id: thread_id}, messageNextCursor: cursor} when not is_nil(cursor) ->
        {:noreply, load_detail(socket, thread_id, cursor)}

      _state ->
        {:noreply, socket}
    end
  end

  def handle("refresh", _params, socket), do: {:noreply, refresh(socket)}
  def handle(_action, _params, socket), do: failure(socket, :invalid_request)

  def refresh(%{assigns: %{scene: nil}} = socket), do: socket

  def refresh(socket) do
    %{current_scope: scope, project: project, scene: scene, comments: state} = socket.assigns

    case Projects.list_scene_comment_pins(scope, project.id, scene.id) do
      {:ok, pins} ->
        can_comment = match?({:ok, _, _}, Projects.authorize(scope, project.id, :edit_content))

        socket =
          socket
          |> assign(:comment_pins, pins)
          |> put_state(%{canComment: can_comment, placing: can_comment && state.placing})

        refresh_open(socket, state)

      _error ->
        clear(socket)
    end
  end

  defp refresh_open(socket, %{open: false}), do: socket

  defp refresh_open(socket, state) do
    socket = socket |> load_threads() |> load_members()

    if state.thread, do: load_detail(socket, state.thread.id), else: socket
  end

  def refresh_result({:noreply, socket}), do: {:noreply, refresh(socket)}
  def refresh_result({:reply, reply, socket}), do: {:reply, reply, refresh(socket)}

  defp mutate("mode", params, socket) do
    active? = params["active"] == true

    socket =
      socket
      |> close()
      |> maybe_select_tool(active?)
      |> put_state(%{placing: active?})

    {:reply, %{ok: true}, socket}
  end

  defp mutate("place", params, socket) do
    case position(params) do
      {:ok, position} ->
        draft_id =
          if params["moving_draft"] == true && socket.assigns.comments.draftId,
            do: socket.assigns.comments.draftId,
            else: Ecto.UUID.generate()

        socket =
          socket
          |> close()
          |> maybe_select_tool(true)
          |> assign(:right_panel, nil)
          |> put_state(%{
            open: true,
            presentation: "canvas",
            draftPosition: position,
            draftId: draft_id,
            thread: nil,
            messages: [],
            messageNextCursor: nil
          })
          |> refresh()

        {:reply, %{ok: true}, socket}

      {:error, reason} ->
        failure(socket, reason)
    end
  end

  defp mutate("move", params, socket) do
    thread_id = positive_id(params["thread_id"])

    with {:ok, _detail} <- current_scene_thread(socket, thread_id),
         {:ok, position} <- position(params),
         {:ok, thread} <-
           Projects.move_comment_thread(
             socket.assigns.current_scope,
             socket.assigns.project.id,
             thread_id,
             position,
             positive_id(params["expected_revision"])
           ) do
      {:reply, %{ok: true, thread: thread}, refresh(socket)}
    else
      {:error, reason} -> failure(refresh(socket), reason)
    end
  end

  defp mutate("create", params, socket) do
    %{current_scope: scope, project: project, scene: scene} = socket.assigns
    attrs = Map.take(params, ~w(body client_request_id mention_user_ids position))

    scope
    |> Projects.create_scene_canvas_comment(project.id, scene.id, attrs)
    |> mutation_result(socket)
  end

  defp mutate("reply", params, socket) do
    thread_id = positive_id(params["thread_id"])

    case current_scene_thread(socket, thread_id) do
      {:ok, _detail} ->
        socket.assigns.current_scope
        |> Projects.reply_to_comment_thread(
          socket.assigns.project.id,
          thread_id,
          Map.take(params, ~w(body parent_id client_request_id mention_user_ids))
        )
        |> mutation_result(socket)

      _error ->
        failure(socket, :not_found)
    end
  end

  defp mutate("set_status", params, socket) do
    thread_id = positive_id(params["thread_id"])

    with {:ok, _detail} <- current_scene_thread(socket, thread_id),
         {:ok, _thread} <-
           Projects.set_comment_thread_status(
             socket.assigns.current_scope,
             socket.assigns.project.id,
             thread_id,
             params["status"],
             positive_id(params["expected_revision"])
           ) do
      {:reply, %{ok: true}, socket |> refresh() |> select_thread(thread_id)}
    else
      {:error, reason} -> failure(refresh(socket), reason)
    end
  end

  defp mutation_result({:ok, %{thread: %{id: thread_id}}}, socket) do
    {:reply, %{ok: true}, socket |> refresh() |> select_thread(thread_id)}
  end

  defp mutation_result({:error, reason}, socket), do: failure(socket, reason)

  defp open_linked_thread(socket, thread_id) do
    socket |> put_state(%{presentation: "canvas"}) |> select_thread(thread_id)
  end

  defp select_thread(socket, nil), do: put_state(socket, %{error: error_message(:not_found)})

  defp select_thread(socket, thread_id) do
    socket
    |> assign(:right_panel, nil)
    |> put_state(%{open: true, placing: false, draftPosition: nil, draftId: nil, error: nil})
    |> load_threads()
    |> load_members()
    |> load_detail(thread_id)
    |> focus_selected_thread()
  end

  defp load_threads(socket, cursor \\ nil) do
    %{current_scope: scope, project: project, scene: scene, comments: state} = socket.assigns
    opts = [status: state.statusFilter, cursor: cursor]

    case Projects.list_scene_comment_threads(scope, project.id, scene.id, opts) do
      {:ok, %{threads: threads, next_cursor: next_cursor}} ->
        threads = if cursor, do: Enum.uniq_by(state.threads ++ threads, & &1.id), else: threads
        put_state(socket, %{threads: threads, nextCursor: next_cursor})

      _error ->
        clear(socket)
    end
  end

  defp load_detail(socket, thread_id, cursor \\ nil) do
    case current_scene_thread(socket, thread_id, cursor: cursor) do
      {:ok, %{thread: thread, messages: messages, next_cursor: next_cursor}} ->
        messages =
          if cursor do
            (messages ++ socket.assigns.comments.messages)
            |> Enum.uniq_by(& &1.id)
            |> Enum.sort_by(& &1.id)
          else
            messages
          end

        available? = thread.source.status == "available"
        presentation = if available?, do: socket.assigns.comments.presentation, else: "panel"

        socket
        |> put_state(%{
          thread: thread,
          messages: messages,
          messageNextCursor: next_cursor,
          draftPosition: nil,
          draftId: nil,
          presentation: presentation
        })
        |> assign(:comment_focus_thread_id, if(available?, do: socket.assigns.comment_focus_thread_id))

      _error ->
        if match?({:ok, _, _}, authorize_read(socket)) do
          socket
          |> assign(:comment_focus_thread_id, nil)
          |> put_state(%{
            thread: nil,
            messages: [],
            messageNextCursor: nil,
            draftPosition: nil,
            draftId: nil,
            presentation: "panel",
            error: error_message(:not_found)
          })
        else
          clear(socket)
        end
    end
  end

  defp load_members(socket) do
    case Projects.list_comment_members(socket.assigns.current_scope, socket.assigns.project.id) do
      {:ok, members} -> put_state(socket, %{members: members})
      _error -> clear(socket)
    end
  end

  defp current_scene_thread(socket, thread_id, opts \\ []) do
    with {:ok, %{thread: %{source: %{scene_id: scene_id}}} = detail} <-
           Projects.get_comment_thread(socket.assigns.current_scope, socket.assigns.project.id, thread_id, opts),
         true <- scene_id == socket.assigns.scene.id do
      {:ok, detail}
    else
      _error -> {:error, :not_found}
    end
  end

  defp authorize_read(socket), do: Projects.authorize(socket.assigns.current_scope, socket.assigns.project.id, :view)

  defp focus_selected_thread(socket) do
    thread_id =
      case socket.assigns.comments.thread do
        %{id: id, source: %{status: "available"}} -> id
        _thread -> nil
      end

    assign(socket, :comment_focus_thread_id, thread_id)
  end

  defp maybe_select_tool(%{assigns: %{edit_mode: true}} = socket, true) do
    socket
    |> assign(:active_tool, :select)
    |> push_event("tool_changed", %{tool: "select"})
  end

  defp maybe_select_tool(socket, _active?), do: socket

  defp position(%{"x" => x, "y" => y}) when is_number(x) and is_number(y) and x >= 0 and x <= 100 and y >= 0 and y <= 100,
    do: {:ok, %{x: x, y: y}}

  defp position(_params), do: {:error, :invalid_position}

  defp positive_id(id) when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807, do: id

  defp positive_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {value, ""} when value > 0 and value <= 9_223_372_036_854_775_807 -> value
      _invalid -> nil
    end
  end

  defp positive_id(_id), do: nil

  defp put_state(socket, attrs), do: assign(socket, :comments, Map.merge(socket.assigns.comments, attrs))

  defp clear(socket) do
    socket
    |> assign(:comments, %{empty_state() | open: socket.assigns.comments.open, error: error_message(:not_found)})
    |> assign(:comment_pins, [])
    |> assign(:comment_focus_thread_id, nil)
  end

  defp failure(socket, reason) do
    socket = if match?({:ok, _, _}, authorize_read(socket)), do: socket, else: clear(socket)
    message = error_message(reason)
    {:reply, %{ok: false, error: message}, put_state(socket, %{error: message})}
  end

  defp error_message(:stale), do: dgettext("scenes", "This conversation changed. Review the latest state and try again.")

  defp error_message(reason) when reason in [:not_found, :unauthorized, :unavailable, :source_unavailable] do
    dgettext("scenes", "This conversation or its source is no longer available.")
  end

  defp error_message(_reason), do: dgettext("scenes", "Could not save the comment. Check the text and selected mentions.")

  defp empty_state do
    %{
      open: false,
      presentation: "panel",
      placing: false,
      draftPosition: nil,
      draftId: nil,
      threads: [],
      nextCursor: nil,
      thread: nil,
      messages: [],
      messageNextCursor: nil,
      members: [],
      canComment: false,
      statusFilter: "open",
      error: nil
    }
  end
end
