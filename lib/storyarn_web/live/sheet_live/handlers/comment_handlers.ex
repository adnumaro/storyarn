defmodule StoryarnWeb.SheetLive.Handlers.CommentHandlers do
  @moduledoc false

  use Gettext, backend: Storyarn.Gettext

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [connected?: 1]

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
  def loaded(%{assigns: %{sheet: nil}} = socket), do: socket

  def loaded(socket) do
    if connected?(socket) do
      Projects.subscribe_sheet_comments(
        socket.assigns.current_scope,
        socket.assigns.project.id,
        socket.assigns.sheet.id
      )
    end

    refresh(socket)
  end

  def unload(socket) do
    if socket.assigns[:sheet] do
      Projects.unsubscribe_sheet_comments(socket.assigns.project.id, socket.assigns.sheet.id)
    end

    socket
  end

  def close(%{assigns: %{comments: _state}} = socket) do
    socket
    |> put_state(%{
      open: false,
      placing: false,
      selectedBlockId: nil,
      selectedBlockLabel: nil,
      draftPosition: nil,
      draftId: nil,
      error: nil
    })
    |> assign(:comment_focus_thread_id, nil)
  end

  def close(socket), do: socket

  def handle_params(%{assigns: %{compact: true}} = socket, _params), do: socket
  def handle_params(%{assigns: %{sheet: nil}} = socket, _params), do: socket

  def handle_params(socket, %{"thread" => thread_id}) do
    open_linked_thread(socket, positive_id(thread_id))
  end

  def handle_params(socket, _params), do: socket

  def handle(_action, _params, %{assigns: %{compact: true}} = socket), do: failure(socket, :unavailable)

  def handle(_action, _params, %{assigns: %{sheet: nil}} = socket), do: failure(socket, :unavailable)

  def handle(action, params, socket) when action in @mutations do
    Authorize.with_authorization(
      socket,
      :edit_content,
      &mutate(action, params, &1),
      fn current, _reason -> failure(clear(current), :unauthorized) end
    )
  end

  def handle("open", params, socket) do
    with {:ok, _project, _membership} <- authorize_read(socket),
         {:ok, block_id} <- optional_block(socket, params["block_id"]) do
      block_label = selected_block_label(socket, block_id)

      socket =
        socket
        |> assign(:current_tab, "content")
        |> put_state(%{
          open: true,
          presentation: "panel",
          placing: false,
          selectedBlockId: block_id,
          selectedBlockLabel: block_label,
          draftPosition: nil,
          draftId: nil,
          thread: nil,
          messages: [],
          messageNextCursor: nil,
          error: nil
        })
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

  def refresh(%{assigns: %{sheet: nil}} = socket), do: socket

  def refresh(socket) do
    %{current_scope: scope, project: project, sheet: sheet, comments: state} = socket.assigns

    case Projects.list_sheet_comment_pins(scope, project.id, sheet.id) do
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

  def refresh_result({:noreply, socket}), do: {:noreply, refresh(socket)}
  def refresh_result({:reply, reply, socket}), do: {:reply, reply, refresh(socket)}

  defp refresh_open(socket, %{open: false}), do: socket

  defp refresh_open(socket, state) do
    socket = socket |> load_threads() |> load_members()

    if state.thread do
      load_detail(socket, state.thread.id)
    else
      refresh_selected_source(socket, state.selectedBlockId)
    end
  end

  defp refresh_selected_source(socket, nil), do: socket

  defp refresh_selected_source(socket, block_id) do
    case optional_block(socket, block_id) do
      {:ok, _block_id} ->
        put_state(socket, %{selectedBlockLabel: selected_block_label(socket, block_id)})

      _unavailable ->
        socket
        |> assign(:comment_focus_thread_id, nil)
        |> put_state(%{
          selectedBlockId: nil,
          selectedBlockLabel: nil,
          draftPosition: nil,
          draftId: nil,
          presentation: "panel",
          error: error_message(:source_unavailable)
        })
    end
  end

  defp mutate("mode", params, socket) do
    active? = params["active"] == true

    socket =
      socket
      |> close()
      |> assign(:current_tab, "content")
      |> put_state(%{placing: active?})

    {:reply, %{ok: true}, socket}
  end

  defp mutate("place", params, socket) do
    with {:ok, block_id} <- required_block(socket, params["block_id"]),
         {:ok, position} <- position(params) do
      block_label = selected_block_label(socket, block_id)

      draft_id =
        if params["moving_draft"] == true && socket.assigns.comments.draftId,
          do: socket.assigns.comments.draftId,
          else: Ecto.UUID.generate()

      socket =
        socket
        |> close()
        |> assign(:current_tab, "content")
        |> put_state(%{
          open: true,
          presentation: "canvas",
          selectedBlockId: block_id,
          selectedBlockLabel: block_label,
          draftPosition: position,
          draftId: draft_id,
          thread: nil,
          messages: [],
          messageNextCursor: nil
        })
        |> refresh()

      {:reply, %{ok: true}, socket}
    else
      {:error, reason} -> failure(socket, reason)
    end
  end

  defp mutate("move", params, socket) do
    thread_id = positive_id(params["thread_id"])
    expected_revision = positive_id(params["expected_revision"] || params["revision"])

    with {:ok, _detail} <- current_sheet_thread(socket, thread_id),
         {:ok, position} <- position(params),
         {:ok, thread} <-
           Projects.move_comment_thread(
             socket.assigns.current_scope,
             socket.assigns.project.id,
             thread_id,
             position,
             expected_revision
           ) do
      {:reply, %{ok: true, thread: thread}, refresh(socket)}
    else
      {:error, reason} -> failure(refresh(socket), reason)
    end
  end

  defp mutate("create", params, socket) do
    %{current_scope: scope, project: project, sheet: sheet} = socket.assigns
    attrs = Map.take(params, ~w(body client_request_id mention_user_ids position))

    result =
      case required_block(socket, params["block_id"]) do
        {:ok, block_id} ->
          Projects.create_sheet_block_comment(scope, project.id, sheet.id, block_id, attrs)

        {:error, _reason} = error ->
          error
      end

    mutation_result(result, socket)
  end

  defp mutate("reply", params, socket) do
    thread_id = positive_id(params["thread_id"])

    case current_sheet_thread(socket, thread_id) do
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
    expected_revision = positive_id(params["expected_revision"] || params["revision"])

    with {:ok, _detail} <- current_sheet_thread(socket, thread_id),
         {:ok, _thread} <-
           Projects.set_comment_thread_status(
             socket.assigns.current_scope,
             socket.assigns.project.id,
             thread_id,
             params["status"],
             expected_revision
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
    socket
    |> assign(:current_tab, "content")
    |> put_state(%{presentation: "canvas"})
    |> select_thread(thread_id)
  end

  defp select_thread(socket, nil), do: put_state(socket, %{error: error_message(:not_found)})

  defp select_thread(socket, thread_id) do
    socket
    |> put_state(%{open: true, placing: false, draftPosition: nil, draftId: nil, error: nil})
    |> load_threads()
    |> load_members()
    |> load_detail(thread_id)
    |> focus_selected_thread()
  end

  defp load_threads(socket, cursor \\ nil) do
    %{current_scope: scope, project: project, sheet: sheet, comments: state} = socket.assigns
    opts = [status: state.statusFilter, cursor: cursor]

    case Projects.list_sheet_comment_threads(scope, project.id, sheet.id, opts) do
      {:ok, %{threads: threads, next_cursor: next_cursor}} ->
        threads = if cursor, do: Enum.uniq_by(state.threads ++ threads, & &1.id), else: threads
        put_state(socket, %{threads: threads, nextCursor: next_cursor})

      _error ->
        clear(socket)
    end
  end

  defp load_detail(socket, thread_id, cursor \\ nil) do
    case current_sheet_thread(socket, thread_id, cursor: cursor) do
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
        block_id = if available?, do: thread.source.id
        block_label = selected_block_label(socket, block_id)
        presentation = if available?, do: socket.assigns.comments.presentation, else: "panel"

        socket
        |> put_state(%{
          thread: thread,
          messages: messages,
          messageNextCursor: next_cursor,
          selectedBlockId: block_id,
          selectedBlockLabel: block_label,
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
            selectedBlockId: nil,
            selectedBlockLabel: nil,
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

  defp current_sheet_thread(socket, thread_id, opts \\ []) do
    with {:ok, %{thread: %{source: %{type: "sheet_block", sheet_id: sheet_id}}} = detail} <-
           Projects.get_comment_thread(
             socket.assigns.current_scope,
             socket.assigns.project.id,
             thread_id,
             opts
           ),
         true <- sheet_id == socket.assigns.sheet.id do
      {:ok, detail}
    else
      _error -> {:error, :not_found}
    end
  end

  defp optional_block(_socket, nil), do: {:ok, nil}
  defp optional_block(socket, raw_id), do: required_block(socket, raw_id)

  defp required_block(socket, raw_id) do
    with block_id when is_integer(block_id) <- positive_id(raw_id),
         true <- sheet_block?(socket, block_id) do
      {:ok, block_id}
    else
      _error -> {:error, :not_found}
    end
  end

  defp sheet_block?(socket, block_id) do
    not is_nil(find_sheet_block(socket, block_id))
  end

  defp selected_block_label(_socket, nil), do: nil

  defp selected_block_label(socket, block_id) do
    with %{config: config} <- find_sheet_block(socket, block_id),
         label when is_binary(label) <- config["label"],
         label when label != "" <- String.trim(label) do
      String.slice(label, 0, 120)
    else
      _missing_label -> nil
    end
  end

  defp find_sheet_block(socket, block_id) do
    Enum.find(socket.assigns.blocks, &(&1.id == block_id)) ||
      Enum.find_value(socket.assigns.inherited_groups, fn group ->
        Enum.find(group.blocks, &(&1.id == block_id))
      end)
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
    |> assign(:comments, %{
      empty_state()
      | open: socket.assigns.comments.open,
        error: error_message(:not_found)
    })
    |> assign(:comment_pins, [])
    |> assign(:comment_focus_thread_id, nil)
  end

  defp failure(socket, reason) do
    socket = if match?({:ok, _, _}, authorize_read(socket)), do: socket, else: clear(socket)
    message = error_message(reason)
    {:reply, %{ok: false, error: message}, put_state(socket, %{error: message})}
  end

  defp error_message(:stale), do: dgettext("sheets", "This conversation changed. Review the latest state and try again.")

  defp error_message(reason) when reason in [:not_found, :unauthorized, :unavailable, :source_unavailable],
    do: dgettext("sheets", "This conversation or its source is no longer available.")

  defp error_message(_reason), do: dgettext("sheets", "Could not save the comment. Check the text and selected mentions.")

  defp empty_state do
    %{
      open: false,
      presentation: "panel",
      placing: false,
      selectedBlockId: nil,
      selectedBlockLabel: nil,
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
