defmodule StoryarnWeb.IdeationLive.Board do
  @moduledoc false
  use StoryarnWeb, :live_view

  alias Storyarn.Ideation
  alias Storyarn.Platform.Collaboration
  alias Storyarn.Platform.Shared.StringUtils
  alias Storyarn.Projects
  alias Storyarn.Workspaces
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.IdeationLive.Handlers.IdeaHandlers
  alias StoryarnWeb.IdeationLive.Handlers.RoundHandlers
  alias StoryarnWeb.IdeationLive.Handlers.SessionHandlers
  alias StoryarnWeb.IdeationLive.Handlers.TimerHandlers
  alias StoryarnWeb.IdeationLive.Helpers.BoardData
  alias StoryarnWeb.IdeationLive.Helpers.Params
  alias StoryarnWeb.IdeationLive.Helpers.Replies
  alias StoryarnWeb.IdeationLive.Helpers.RoundData
  alias StoryarnWeb.Live.Shared.CollaborationHelpers
  alias StoryarnWeb.Live.Shared.ProjectChromeHelpers

  @session_writes ~w(create_session update_session assign_responsibilities archive_session reopen_session recover_session purge_session)
  @idea_writes ~w(create_idea save_idea delete_idea restore_idea move_idea connect_ideas prepare_reveal reveal_ideas)
  @round_writes ~w(create_round update_round cancel_round start_round close_round)
  @timer_writes ~w(start_timer pause_timer resume_timer extend_timer cancel_timer set_contributions_open)

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.ProjectLayout.project
      socket={@socket}
      flash={@flash}
      project={@project}
      workspace={@workspace}
      current_scope={@current_scope}
      current_user={@current_user}
      membership={@membership}
      urls={@urls}
      active_tool={:brainstorming}
      online_users={@online_users}
      canvas_mode={@session_id != nil}
      sidebar_module={StoryarnWeb.IdeationLive.Sidebar}
      sidebar_session={
        %{
          "project_id" => @project.id,
          "workspace_id" => @workspace.id,
          "current_scope" => @current_scope,
          "base_url" => @urls.tools["brainstorming"],
          "locale" => @locale
        }
      }
    >
      <.vue
        :if={@board.session}
        v-component="live/ideation/BoardHeader"
        v-socket={@socket}
        v-diff={true}
        v-inject:top-left="project-layout"
        id="brainstorming-header"
        session={@board.session}
        can-manage={@board.can_manage}
        can-edit={@board.can_edit}
        epoch={@epoch}
        rounds={@board.rounds}
        rounds-next={@board.rounds_next}
        active-round={@board.active_round}
        timer={@board.timer}
      />
      <.vue
        v-component="live/ideation/BrainstormingBoard"
        v-socket={@socket}
        v-inject="project-layout"
        id="brainstorming-board"
        class="contents"
        board={
          Map.merge(@board, %{epoch: @epoch, loading: @refresh_running != nil, error: @board_error})
        }
        base-url={@urls.tools["brainstorming"]}
      />
    </StoryarnWeb.Components.ProjectLayout.project>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    project_id = socket.assigns.project.id

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Storyarn.PubSub, ProjectChromeHelpers.shell_topic(project_id))

      Phoenix.PubSub.subscribe(
        Storyarn.PubSub,
        "project:#{project_id}:ideation-navigation:#{node(socket.transport_pid)}:#{inspect(socket.transport_pid)}"
      )

      Ideation.subscribe_sessions(socket.assigns.current_scope, project_id)
      Projects.subscribe_project_ownership_changes(project_id)
      Projects.subscribe_project_membership_changes(project_id)
      Workspaces.subscribe_workspace_ownership_changes(socket.assigns.workspace.id)
      Workspaces.subscribe_workspace_membership_changes(socket.assigns.workspace.id)
    end

    {:ok,
     socket
     |> assign(:page_title, gettext("Brainstorming"))
     |> assign(:board, BoardData.empty())
     |> assign(:board_error, nil)
     |> assign(:epoch, Ecto.UUID.generate())
     |> assign(:session_id, nil)
     |> assign(:subscribed_session, nil)
     |> assign(:canvas_scope, nil)
     |> assign(:canvas_ready, false)
     |> assign(:last_cursor_at, 0)
     |> assign(:filters, %{
       session_status: :open,
       session_before: nil,
       idea_before: nil,
       round_id: :all,
       round_before: nil
     })
     |> assign(:refresh_timer, nil)
     |> assign(:refresh_running, nil)
     |> assign(:refresh_dirty, false)
     |> assign(:online_users, ProjectChromeHelpers.initial_online_users(project_id))}
  end

  @impl true
  def handle_params(params, _url, socket) do
    case Params.optional_id(params["id"]) do
      {:ok, id} ->
        socket = socket |> subscribe_session(id) |> assign(:session_id, id)
        filters = %{socket.assigns.filters | idea_before: nil, round_id: :all, round_before: nil}
        socket = assign(socket, :filters, filters)
        # A route transition invalidates reads started for the previous session.
        socket = assign(socket, :refresh_running, nil)
        {:noreply, load_now(socket)}

      {:error, _} ->
        {:noreply,
         socket
         |> subscribe_session(nil)
         |> canvas_subscription(nil)
         |> assign(session_id: nil, refresh_running: nil, board: BoardData.empty(), board_error: "not_found")}
    end
  end

  @impl true
  def handle_event(event, params, socket)
      when event in @session_writes or event in @idea_writes or event in @round_writes or event in @timer_writes do
    Authorize.with_authorization(socket, :edit_content, fn socket -> write(event, params, socket) end, fn socket,
                                                                                                          reason ->
      {:reply, Replies.error(reason), reload_access(socket)}
    end)
  end

  def handle_event("session_history", params, socket) do
    with :ok <- current_session(params, socket),
         {:ok, before_id} <- Params.optional_id(params["before_id"]),
         {:ok, rows} <-
           Ideation.list_session_revisions(
             socket.assigns.current_scope,
             socket.assigns.project.id,
             socket.assigns.session_id,
             before_id: before_id
           ) do
      history = Enum.map(rows, &Map.take(&1, [:id, :number, :actor_id, :action, :snapshot, :inserted_at]))
      {:reply, %{status: "ok", value: BoardData.page(history)}, socket}
    else
      {:error, reason} -> {:reply, Replies.error(reason), read_result_socket(socket, {:error, reason})}
    end
  end

  def handle_event("browse_sessions", params, socket) do
    case Params.optional_id(params["before_id"]) do
      {:ok, before_id} ->
        status = Params.filter(params["status"], [:open, :archived, :replaced], :open)
        filters = %{socket.assigns.filters | session_status: status, session_before: before_id}
        {:reply, %{status: "ok"}, socket |> assign(:filters, filters) |> refresh()}

      {:error, reason} ->
        {:reply, Replies.error(reason), socket}
    end
  end

  def handle_event("browse_ideas", params, socket) do
    with :ok <- current_session(params, socket),
         {:ok, before_id} <- Params.optional_id(params["before_id"]) do
      filters = %{socket.assigns.filters | idea_before: before_id}
      {:reply, %{status: "ok"}, socket |> assign(:filters, filters) |> refresh()}
    else
      {:error, reason} -> {:reply, Replies.error(reason), socket}
    end
  end

  def handle_event("filter_round", params, socket) do
    with :ok <- current_session(params, socket),
         {:ok, round_id} <- Params.round_filter(params["round_id"]),
         {:ok, before_id} <- Params.optional_id(params["before_id"]),
         :ok <-
           RoundData.validate_filter(
             socket.assigns.current_scope,
             socket.assigns.project.id,
             socket.assigns.session_id,
             round_id
           ) do
      filters = %{socket.assigns.filters | round_id: round_id, idea_before: before_id}
      {:reply, %{status: "ok"}, socket |> assign(:filters, filters) |> refresh()}
    else
      {:error, reason} -> {:reply, Replies.error(reason), read_result_socket(socket, {:error, reason})}
    end
  end

  def handle_event("browse_rounds", params, socket) do
    with :ok <- current_session(params, socket),
         {:ok, before_id} <- Params.optional_id(params["before_id"]) do
      filters = %{socket.assigns.filters | round_before: before_id}
      {:reply, %{status: "ok"}, socket |> assign(:filters, filters) |> refresh()}
    else
      {:error, reason} -> {:reply, Replies.error(reason), socket}
    end
  end

  def handle_event("open_session", params, socket) do
    with :ok <- current_epoch(params, socket),
         {:ok, id} <- Params.positive(params["id"]),
         {:ok, _} <- Ideation.get_session(socket.assigns.current_scope, socket.assigns.project.id, id) do
      {:reply, %{status: "ok"},
       push_patch(socket,
         to: ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/brainstorming/#{id}"
       )}
    else
      {:error, reason} -> {:reply, Replies.error(reason), socket}
    end
  end

  def handle_event("set_private_mode", params, socket) do
    Authorize.with_authorization(
      socket,
      :edit_content,
      fn socket ->
        with :ok <- current_session(params, socket),
             {:ok, revision} <- Params.positive(params["revision"]) do
          result =
            Ideation.set_private_mode(
              socket.assigns.current_scope,
              socket.assigns.project.id,
              socket.assigns.session_id,
              revision,
              params["enabled"]
            )

          {:reply, Replies.result(result), refresh(socket)}
        else
          {:error, reason} -> {:reply, Replies.error(reason), socket}
        end
      end,
      fn socket, reason -> {:reply, Replies.error(reason), reload_access(socket)} end
    )
  end

  def handle_event("canvas_cursor", %{"x" => x, "y" => y} = params, socket)
      when is_number(x) and is_number(y) and abs(x) <= 1_000_000 and abs(y) <= 1_000_000 do
    now = System.monotonic_time(:millisecond)

    with :ok <- current_session(params, socket),
         true <- socket.assigns.last_cursor_at == 0 or now - socket.assigns.last_cursor_at >= 80,
         true <- cursors_enabled?(socket) do
      user = socket.assigns.current_scope.user

      payload = %{
        session_id: socket.assigns.session_id,
        user_id: user.id,
        name: StringUtils.present_label(user.display_name, gettext("Member")),
        color: Collaboration.user_color(user.id),
        x: x,
        y: y
      }

      Collaboration.broadcast_change_from(self(), socket.assigns.canvas_scope, :brainstorming_cursor, payload)
      {:noreply, assign(socket, :last_cursor_at, now)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("canvas_cursor", _, socket), do: {:noreply, socket}

  def handle_event("board_action", %{"action" => action} = params, socket) when action in ~w(settings reveal) do
    case current_session(params, socket) do
      :ok ->
        {:noreply,
         push_event(socket, "board_action", %{
           action: action,
           epoch: socket.assigns.epoch,
           session_id: socket.assigns.session_id
         })}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("board_action", _params, socket), do: {:reply, Replies.error(:invalid_parameters), socket}

  def handle_event("sync_board", _params, socket) do
    case Projects.authorize(socket.assigns.current_scope, socket.assigns.project.id, :view) do
      {:ok, _, _} -> {:reply, %{status: "ok", epoch: socket.assigns.epoch}, refresh(socket)}
      {:error, reason} -> {:reply, Replies.error(reason), lose_access(socket)}
    end
  end

  @impl true
  def handle_info(
        {:remote_change, :brainstorming_cursor, %{session_id: id} = payload},
        %{assigns: %{session_id: id}} = socket
      ) do
    socket =
      if cursors_enabled?(socket) and Enum.any?(socket.assigns.board.members, &(&1.id == payload.user_id)),
        do: push_event(socket, "canvas_cursor", Map.put(payload, :epoch, socket.assigns.epoch)),
        else: socket

    {:noreply, socket}
  end

  def handle_info({:online_users, users}, socket) do
    known_ids = MapSet.new(socket.assigns.online_users, & &1.user_id)
    member_ids = MapSet.new(socket.assigns.board.members, & &1.id)
    new_member? = Enum.any?(users, &(!MapSet.member?(known_ids, &1.user_id) and !MapSet.member?(member_ids, &1.user_id)))
    socket = assign(socket, :online_users, users)
    {:noreply, if(new_member?, do: refresh(socket), else: socket)}
  end

  def handle_info({:ideation_sessions_changed, _project_id}, socket),
    do: {:noreply, socket |> assign(:canvas_ready, false) |> refresh()}

  def handle_info({:ideation_changed, id}, %{assigns: %{session_id: id}} = socket), do: {:noreply, refresh(socket)}

  def handle_info({event, %{project_id: id}}, %{assigns: %{project: %{id: id}}} = socket)
      when event in [:project_membership_changed, :project_ownership_transferred], do: {:noreply, reload_access(socket)}

  def handle_info({event, %{workspace_id: id}}, %{assigns: %{workspace: %{id: id}}} = socket)
      when event in [:workspace_membership_changed, :workspace_ownership_transferred],
      do: {:noreply, reload_access(socket)}

  def handle_info(
        {:open_ideation_session, %{project_id: project_id, session_id: id}},
        %{assigns: %{project: %{id: project_id}}} = socket
      ) do
    case Ideation.get_session(socket.assigns.current_scope, project_id, id) do
      {:ok, _session} ->
        {:noreply,
         push_patch(socket,
           to:
             ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/brainstorming/#{id}"
         )}

      {:error, _reason} ->
        {:noreply, reload_access(socket)}
    end
  end

  def handle_info({:project_restored, _restore_id}, socket) do
    socket =
      socket
      |> canvas_subscription(nil)
      |> reset_epoch("project_restored")
      |> assign(:filters, %{socket.assigns.filters | idea_before: nil, round_id: :all, round_before: nil})
      |> assign(:board, BoardData.empty())
      |> refresh()

    {:noreply, socket}
  end

  def handle_info(:refresh_board, socket) do
    socket = assign(socket, :refresh_timer, nil)

    if socket.assigns.refresh_running do
      {:noreply, assign(socket, :refresh_dirty, true)}
    else
      %{current_scope: scope, project: project, session_id: id, filters: filters} = socket.assigns
      token = make_ref()

      socket =
        socket
        |> assign(refresh_running: token, refresh_dirty: false)
        |> start_async({:board, token}, fn -> BoardData.load(scope, project.id, id, filters) end)

      {:noreply, socket}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_async({:board, token}, result, %{assigns: %{refresh_running: token}} = socket) do
    dirty? = socket.assigns.refresh_dirty
    socket = assign(socket, refresh_running: nil, refresh_dirty: false)

    socket =
      if dirty? do
        refresh(socket)
      else
        accept_read(socket, result)
      end

    {:noreply, socket}
  end

  def handle_async({:board, _old_token}, _result, socket), do: {:noreply, socket}

  defp write(event, params, socket) do
    with :ok <- current_epoch(params, socket),
         :ok <-
           if(event in (@idea_writes ++ @round_writes ++ @timer_writes),
             do: current_session(params, socket),
             else: :ok
           ) do
      result =
        cond do
          event in @session_writes ->
            SessionHandlers.run(event, socket.assigns.current_scope, socket.assigns.project.id, params)

          event in @round_writes ->
            RoundHandlers.run(
              event,
              socket.assigns.current_scope,
              socket.assigns.project.id,
              socket.assigns.session_id,
              params
            )

          event in @timer_writes ->
            TimerHandlers.run(
              event,
              socket.assigns.current_scope,
              socket.assigns.project.id,
              socket.assigns.session_id,
              params
            )

          true ->
            IdeaHandlers.run(
              event,
              socket.assigns.current_scope,
              socket.assigns.project.id,
              socket.assigns.session_id,
              params
            )
        end

      reply =
        case result do
          {:conflict, conflict} -> %{status: "conflict", value: conflict}
          other -> Replies.result(other)
        end

      {:reply, reply, refresh(socket)}
    else
      {:error, reason} -> {:reply, Replies.error(reason), socket}
    end
  end

  defp current_epoch(%{"epoch" => epoch}, %{assigns: %{epoch: epoch}}), do: :ok
  defp current_epoch(_, _), do: {:error, :stale_board}

  defp current_session(params, socket) do
    with :ok <- current_epoch(params, socket),
         {:ok, id} <- Params.positive(params["session_id"]),
         true <- id == socket.assigns.session_id do
      :ok
    else
      _ -> {:error, :stale_board}
    end
  end

  defp read_result_socket(socket, {:error, _}) do
    case Projects.authorize(socket.assigns.current_scope, socket.assigns.project.id, :view) do
      {:ok, _, _} -> socket
      {:error, _} -> lose_access(socket)
    end
  end

  defp load_now(socket) do
    %{current_scope: scope, project: project, session_id: id, filters: filters} = socket.assigns
    accept_read(socket, {:ok, BoardData.load(scope, project.id, id, filters)})
  end

  defp reload_access(socket) do
    # Losing edit permission does not imply losing read permission. Reload the
    # authorized projection before deciding whether the client must drop drafts.
    socket |> assign(:refresh_running, nil) |> load_now()
  end

  defp accept_read(socket, {:ok, {:ok, data}}) do
    # A result calculated before access was revoked must not repopulate props.
    case Projects.authorize(socket.assigns.current_scope, socket.assigns.project.id, :view) do
      {:ok, project, membership} ->
        can_edit = Projects.can?(membership.role, :edit_content)
        owner? = project.owner_id == socket.assigns.current_scope.user.id

        data = %{
          data
          | can_edit: can_edit,
            is_owner: owner?,
            can_manage:
              can_edit and data.session != nil and
                (owner? or data.session.facilitator_id == socket.assigns.current_scope.user.id)
        }

        socket
        |> canvas_subscription(if(data.session, do: data.session.id))
        |> assign(board: data, board_error: nil, membership: membership, can_edit: can_edit, canvas_ready: true)

      {:error, _} ->
        lose_access(socket)
    end
  end

  defp accept_read(socket, {:ok, {:error, reason}}) when reason in [:unauthorized, :not_found], do: lose_access(socket)
  defp accept_read(socket, _), do: assign(socket, :board_error, "unavailable")

  defp refresh(%{assigns: %{refresh_running: running}} = socket) when not is_nil(running),
    do: assign(socket, :refresh_dirty, true)

  defp refresh(%{assigns: %{refresh_timer: nil}} = socket),
    do: assign(socket, :refresh_timer, Process.send_after(self(), :refresh_board, 30))

  defp refresh(socket), do: socket

  defp lose_access(socket) do
    socket
    |> canvas_subscription(nil)
    |> reset_epoch("access_changed")
    |> assign(board: BoardData.empty(), board_error: "unauthorized", canvas_ready: false)
  end

  defp cursors_enabled?(%{assigns: %{canvas_ready: true, board_error: nil, board: %{session: session}}} = socket)
       when not is_nil(session) do
    socket.assigns.canvas_scope == {:ideation, session.id} and session.configuration.private_mode != true
  end

  defp cursors_enabled?(_socket), do: false

  defp reset_epoch(socket, reason) do
    epoch = Ecto.UUID.generate()

    socket
    |> assign(epoch: epoch, refresh_running: nil, refresh_dirty: false)
    |> push_event("brainstorming_reset", %{reason: reason, epoch: epoch})
  end

  defp canvas_subscription(socket, id) do
    next = if id, do: {:ideation, id}
    previous = socket.assigns.canvas_scope

    if connected?(socket) and next != previous do
      if previous, do: CollaborationHelpers.teardown(previous, socket.assigns.current_scope.user.id)
      if next, do: CollaborationHelpers.setup(socket, next, socket.assigns.current_scope.user, locks: false)
    end

    assign(socket, :canvas_scope, next)
  end

  defp subscribe_session(socket, id) do
    %{subscribed_session: previous, current_scope: scope, project: project} = socket.assigns

    if connected?(socket) and previous != id do
      if previous, do: Ideation.unsubscribe_ideas(scope, project.id, previous)
      if id, do: Ideation.subscribe_ideas(scope, project.id, id)
    end

    assign(socket, :subscribed_session, id)
  end
end
