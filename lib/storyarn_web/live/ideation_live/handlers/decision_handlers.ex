defmodule StoryarnWeb.IdeationLive.Handlers.DecisionHandlers do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2, assign: 3]

  alias Storyarn.Ideation
  alias Storyarn.Projects
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.IdeationLive.Handlers.CommentHandlers
  alias StoryarnWeb.IdeationLive.Handlers.ReferenceHandlers
  alias StoryarnWeb.IdeationLive.Helpers.DecisionData
  alias StoryarnWeb.IdeationLive.Helpers.Params
  alias StoryarnWeb.IdeationLive.Helpers.Replies

  def init(socket) do
    assign(socket,
      decision_cursor: nil,
      decision_source_query: nil,
      decision_history_cursor: nil,
      decisions: %{
        open: false,
        context: Ecto.UUID.generate(),
        mode: "list",
        items: [],
        nextCursor: nil,
        selected: nil,
        history: [],
        historyNextCursor: nil,
        sources: [],
        sourceResults: [],
        sourceNextCursor: nil,
        searched: false,
        members: [],
        defaultOwnerId: nil,
        canPropose: false,
        error: nil
      }
    )
  end

  def handle(action, params, socket) do
    with true <- socket.assigns.session_id != nil,
         true <- params["epoch"] == socket.assigns.epoch,
         {:ok, id} <- Params.positive(params["session_id"]),
         true <- id == socket.assigns.session_id,
         true <-
           action in ~w(open new) or
             (socket.assigns.decisions.open and params["decision_context"] == socket.assigns.decisions.context) do
      dispatch(action, params, socket)
    else
      _ -> failure(socket, :stale_board)
    end
  end

  def refresh(%{assigns: %{decisions: %{open: false}}} = socket), do: socket

  def refresh(socket) do
    %{current_scope: scope, project: project, session_id: id} = socket.assigns

    with {:ok, session} <- Ideation.get_session(scope, project.id, id),
         true <- session.configuration.private_mode != true,
         {:ok, _, membership} <- Projects.authorize(scope, project.id, :view),
         {:ok, members} <- Projects.list_editor_candidates(scope, project.id),
         {:ok, page} <- decision_pages(scope, project.id, id, socket.assigns.decision_cursor) do
      can_propose = session.status == :open and Projects.can?(membership.role, :edit_content)

      socket
      |> put(%{
        items: Enum.map(page.decisions, &DecisionData.decision(&1, display_members(socket))),
        nextCursor: page.next_cursor,
        members: members,
        defaultOwnerId: if(Enum.any?(members, &(&1.id == session.decision_owner_id)), do: session.decision_owner_id),
        canPropose: can_propose,
        error: nil
      })
      |> refresh_selected()
      |> refresh_sources()
      |> refresh_search()
    else
      _ -> init(socket)
    end
  end

  def preserve_editor(socket), do: failure(socket, :proposal_in_progress)

  defp dispatch("open", %{"from_header" => true}, %{assigns: %{decisions: %{open: true}}} = socket), do: ok(socket)

  defp dispatch("new", _, %{assigns: %{decisions: %{open: true, mode: mode}}} = socket) when mode in ~w(create revise),
    do: preserve_editor(socket)

  defp dispatch("open", _params, socket) do
    socket = socket |> init() |> put(%{open: true}) |> refresh() |> close_other_panels()
    opened(socket)
  end

  defp dispatch("new", params, socket) do
    socket = socket |> init() |> put(%{open: true, mode: "create"}) |> refresh() |> close_other_panels()

    with true <- socket.assigns.decisions.open and socket.assigns.decisions.canPropose,
         {:ok, selection} <- initial_selection(params) do
      if selection == [], do: ok(socket), else: preview(selection, socket)
    else
      false -> failure(socket, :unauthorized)
      {:error, reason} -> failure(socket, reason)
    end
  end

  defp dispatch("close", _, socket), do: ok(init(socket))
  defp dispatch("reload", _, socket), do: ok(refresh(socket))

  defp dispatch("select", params, socket) do
    case Params.positive(params["decision_id"]) do
      {:ok, id} ->
        socket
        |> put(%{
          mode: "detail",
          selected: %{id: id},
          sources: [],
          history: [],
          context: Ecto.UUID.generate(),
          error: nil
        })
        |> refresh()
        |> opened()

      {:error, reason} ->
        failure(socket, reason)
    end
  end

  defp dispatch("begin_revision", params, socket) do
    %{current_scope: scope, project: project, session_id: id} = socket.assigns

    with {:ok, decision_id} <- Params.positive(params["decision_id"]),
         {:ok, version} <- Params.positive(params["revision"]),
         {:ok, decision} <- Ideation.get_decision(scope, project.id, id, decision_id),
         true <- decision.version == version,
         true <- decision.can_revise do
      selected = DecisionData.decision(decision, display_members(socket))

      socket
      |> put(%{
        mode: "revise",
        selected: selected,
        sources: selected.sources,
        sourceResults: [],
        sourceNextCursor: nil,
        searched: false,
        history: [],
        context: Ecto.UUID.generate(),
        error: nil
      })
      |> assign(decision_source_query: nil, decision_history_cursor: nil)
      |> ok()
    else
      {:error, reason} -> failure(refresh(socket), reason)
      _ -> failure(refresh(socket), :stale_decision)
    end
  end

  defp dispatch("load_more", params, socket) do
    with {:ok, cursor} <- Params.positive(params["cursor"]),
         true <- cursor == socket.assigns.decisions.nextCursor do
      socket |> assign(:decision_cursor, cursor) |> refresh() |> ok()
    else
      _ -> failure(socket, :invalid_parameters)
    end
  end

  defp dispatch("search_sources", params, socket) do
    %{current_scope: scope, project: project, session_id: id} = socket.assigns

    with {:ok, before_id} <- Params.optional_id(params["before_id"]),
         {:ok, page} <-
           Ideation.search_decision_sources(scope, project.id, id,
             type: params["type"],
             search: params["search"] || "",
             before_id: before_id
           ) do
      socket
      |> assign(:decision_source_query, %{type: params["type"], search: params["search"] || "", before_id: before_id})
      |> put(%{
        sourceResults: Enum.map(page.sources, &DecisionData.source/1),
        sourceNextCursor: page.next_cursor,
        searched: true,
        error: nil
      })
      |> ok()
    else
      {:error, reason} -> failure(refresh(socket), reason)
    end
  end

  defp dispatch("preview_sources", %{"sources" => sources}, socket), do: preview(sources, socket)

  defp dispatch("refresh_sources", _, socket) do
    preview(socket.assigns.decisions.sources, socket, true)
  end

  defp dispatch("history", params, socket) do
    %{current_scope: scope, project: project, session_id: id, decisions: state} = socket.assigns

    with {:ok, decision_id} <- Params.positive(params["decision_id"]),
         true <- state.selected != nil and state.selected.id == decision_id,
         {:ok, cursor} <- Params.optional_id(params["before_id"]),
         {:ok, page} <- history_pages(scope, project.id, id, decision_id, cursor) do
      socket
      |> assign(:decision_history_cursor, cursor)
      |> put(%{
        history: Enum.map(page.revisions, &DecisionData.history(&1, display_members(socket))),
        historyNextCursor: page.next_cursor,
        error: nil
      })
      |> ok()
    else
      {:error, reason} -> failure(refresh(socket), reason)
      _ -> failure(socket, :invalid_parameters)
    end
  end

  defp dispatch(action, params, socket) when action in ~w(create revise accept) do
    Authorize.with_authorization(socket, :edit_content, &mutate(action, params, &1), fn current, reason ->
      failure(refresh(current), reason)
    end)
  end

  defp dispatch(_, _, socket), do: failure(socket, :invalid_parameters)

  defp mutate("create", params, socket) do
    %{current_scope: scope, project: project, session_id: id} = socket.assigns
    attrs = proposal_attrs(params)
    result(Ideation.propose_decision(scope, project.id, id, attrs), socket)
  end

  defp mutate(action, params, socket) do
    %{current_scope: scope, project: project, session_id: id} = socket.assigns

    with {:ok, decision_id} <- Params.positive(params["decision_id"]),
         {:ok, version} <- Params.positive(params["revision"]) do
      response =
        if action == "accept",
          do: Ideation.accept_decision(scope, project.id, id, decision_id, version, params["request_key"]),
          else: Ideation.revise_decision(scope, project.id, id, decision_id, version, proposal_attrs(params))

      result(response, socket)
    else
      {:error, reason} -> failure(socket, reason)
    end
  end

  defp proposal_attrs(params) do
    params
    |> Map.take(~w(title conclusion reason sources request_key))
    |> Map.put("responsible_id", params["owner_id"])
  end

  defp result({:ok, decision}, socket) do
    socket
    |> put(%{
      selected: %{id: decision.id},
      mode: "detail",
      sources: [],
      history: [],
      context: Ecto.UUID.generate(),
      error: nil
    })
    |> refresh()
    |> ok()
  end

  defp result({:error, reason}, socket), do: failure(refresh(socket), reason)

  defp preview(selection, socket, replace \\ false)
  defp preview([], socket, _replace), do: socket |> put(%{sources: [], error: nil}) |> ok()

  defp preview(selection, socket, replace) when is_list(selection) and length(selection) <= 20 do
    socket = refresh_selected(socket)
    %{current_scope: scope, project: project, session_id: id} = socket.assigns
    ids = Enum.map(selection, &source_identity/1)

    case Ideation.preview_decision_sources(scope, project.id, id, ids) do
      {:ok, sources} ->
        previous = if replace, do: [], else: socket.assigns.decisions.sources

        updated = Enum.map(sources, &preview_source(&1, previous, socket.assigns.decisions))

        # A recycled numeric ID cannot silently replace a previously selected source.
        changed_identity? =
          Enum.any?(selection, fn source ->
            identity = field(source, :identity)
            identity && not Enum.any?(sources, &(&1.identity == identity))
          end)

        if changed_identity?,
          do: failure(refresh(socket), :sources_unavailable),
          else: socket |> put(%{sources: updated, error: nil}) |> ok()

      {:error, reason} ->
        failure(refresh(socket), reason)
    end
  end

  defp preview(_, socket, _replace), do: failure(socket, :invalid_parameters)

  defp preview_source(current, previous, state) do
    case Enum.find(previous, &(&1.identity == current.identity)) do
      nil -> DecisionData.source(current)
      saved -> restore_source(saved, current, state)
    end
  end

  defp refresh_selected(%{assigns: %{decisions: %{selected: nil}}} = socket), do: socket

  defp refresh_selected(socket) do
    %{current_scope: scope, project: project, session_id: id, decisions: state} = socket.assigns

    case Ideation.get_decision(scope, project.id, id, state.selected.id) do
      {:ok, decision} ->
        socket
        |> put(%{selected: DecisionData.decision(decision, display_members(socket))})
        |> refresh_history()

      {:error, _} ->
        init(socket)
    end
  end

  defp refresh_history(%{assigns: %{decisions: %{history: []}}} = socket), do: socket

  defp refresh_history(socket) do
    %{current_scope: scope, project: project, session_id: id, decisions: state} = socket.assigns

    case history_pages(scope, project.id, id, state.selected.id, socket.assigns.decision_history_cursor) do
      {:ok, page} ->
        put(socket, %{
          history: Enum.map(page.revisions, &DecisionData.history(&1, display_members(socket))),
          historyNextCursor: page.next_cursor
        })

      {:error, _} ->
        init(socket)
    end
  end

  defp refresh_search(%{assigns: %{decisions: %{open: false}}} = socket), do: socket
  defp refresh_search(%{assigns: %{decision_source_query: nil}} = socket), do: socket

  defp refresh_search(socket) do
    %{current_scope: scope, project: project, session_id: id, decision_source_query: query} = socket.assigns

    case Ideation.search_decision_sources(scope, project.id, id, Map.to_list(query)) do
      {:ok, page} ->
        put(socket, %{
          sourceResults: Enum.map(page.sources, &DecisionData.source/1),
          sourceNextCursor: page.next_cursor,
          searched: true
        })

      {:error, _} ->
        put(socket, %{sourceResults: [], sourceNextCursor: nil, searched: false})
    end
  end

  defp refresh_sources(%{assigns: %{decisions: %{open: false}}} = socket), do: socket

  defp refresh_sources(socket) do
    %{current_scope: scope, project: project, session_id: id, decisions: state} = socket.assigns

    sources =
      Enum.map(state.sources, fn source ->
        candidate = pinned_source(state, source) || source

        case Ideation.preview_decision_sources(scope, project.id, id, [Map.take(candidate, [:type, :id])]) do
          {:ok, [current]} when current.identity == source.identity ->
            restore_source(source, current, state)

          _ ->
            %{source | available: false, title: "", preview: "", changed: false, currentVersion: nil}
        end
      end)

    put(socket, %{sources: sources})
  end

  defp restore_source(source, current, state) do
    pinned = pinned_source(state, source)

    base =
      cond do
        source.available -> source
        current.version == source.version -> DecisionData.source(current)
        pinned != nil -> pinned
        true -> nil
      end

    source
    |> Map.merge(if(base, do: Map.take(base, [:title, :preview]), else: %{title: "", preview: ""}))
    |> Map.merge(%{
      id: current.id,
      available: base != nil,
      changed: current.version != source.version,
      currentVersion: current.version
    })
  end

  defp pinned_source(%{mode: "revise", selected: %{sources: sources}}, source) do
    Enum.find(sources, fn pinned ->
      pinned.available and pinned.type == source.type and pinned.identity == source.identity and
        pinned.version == source.version
    end)
  end

  defp pinned_source(_, _), do: nil

  defp initial_selection(%{"group_id" => id}) do
    with {:ok, id} <- Params.positive(id), do: {:ok, [%{type: "group", id: id}]}
  end

  defp initial_selection(%{"idea_ids" => ids}) when is_list(ids) and length(ids) in 1..20 do
    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, selected} ->
      case Params.positive(id) do
        {:ok, id} -> {:cont, {:ok, selected ++ [%{type: "idea", id: id}]}}
        error -> {:halt, error}
      end
    end)
  end

  defp initial_selection(params) do
    if Map.has_key?(params, "idea_ids"), do: {:error, :invalid_parameters}, else: {:ok, []}
  end

  # Lists are capped by domain limits. Re-read every displayed page rather than
  # retaining formerly authorized rows when the user loads more.
  defp decision_pages(scope, project_id, id, through, cursor \\ nil, rows \\ []) do
    with {:ok, page} <- Ideation.list_decisions(scope, project_id, id, before_id: cursor) do
      rows = rows ++ page.decisions

      if through && page.next_cursor && page.next_cursor >= through,
        do: decision_pages(scope, project_id, id, through, page.next_cursor, rows),
        else: {:ok, %{page | decisions: rows}}
    end
  end

  defp history_pages(scope, project_id, id, decision_id, through, cursor \\ nil, rows \\ []) do
    with {:ok, page} <- Ideation.decision_history(scope, project_id, id, decision_id, before_id: cursor) do
      rows = rows ++ page.revisions

      if through && page.next_cursor && page.next_cursor >= through,
        do: history_pages(scope, project_id, id, decision_id, through, page.next_cursor, rows),
        else: {:ok, %{page | revisions: rows}}
    end
  end

  defp source_identity(source), do: %{type: field(source, :type), id: field(source, :id)}
  defp field(source, key) when is_map(source), do: Map.get(source, key, Map.get(source, Atom.to_string(key)))
  defp field(_, _), do: nil

  defp close_other_panels(socket), do: socket |> CommentHandlers.init() |> ReferenceHandlers.init()
  defp display_members(socket), do: socket.assigns.board.members
  defp opened(%{assigns: %{decisions: %{open: true}}} = socket), do: ok(socket)
  defp opened(socket), do: failure(socket, :not_found)
  defp ok(socket), do: {:reply, %{status: "ok"}, socket}
  defp put(socket, attrs), do: assign(socket, :decisions, Map.merge(socket.assigns.decisions, attrs))
  defp failure(socket, reason), do: {:reply, Replies.error(reason), put(socket, %{error: code(reason)})}
  defp code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp code(_), do: "unavailable"
end
